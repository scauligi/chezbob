"""Simple code for estimating the value of Chez Bob inventory.

Using actual inventories taken, plus records of purchases and sales, estimate
the daily value of the Chez Bob inventory.  Additionally, estimate cost of
goods sold, profits, and shrinkage.
"""

import datetime, time, re, sys
from decimal import Decimal

from chezbob.bobdb.models import BulkItem, Inventory, Product, Order, OrderItem, ProductSource
from django.db import connection
import django.db.transaction
cursor = connection.cursor()

ONE_DAY = datetime.timedelta(days=1)

def extract(seq, date):
    while seq != []:
        if seq[0][0] > date: return
        yield seq.pop(0)

def check_item(inv, bulkid, price_estimates):
    if bulkid not in inv:
        price = price_estimates.get(bulkid, 0.0)
        inv[bulkid] = {'count': 0, 'cost': 0.0, 'price': price}

def to_decimal(f):
    """Convert a floating-point value to a decimal.

    The result has two digits after the decimal point, suitable for use as a
    currency value."""

    return Decimal(str(f)).quantize(Decimal("0.00"))

def item_name(bulkid):
    return BulkItem.objects.get(bulkid=bulkid).description

def generate_inventory_report(start, end=None):
    """Generate a report of changes to inventory, including sales and shrinkage.

    This function is a generator which describes events that result in changes
    to inventory.  Items reported include:
      - Initial inventory values
      - Deliveries
      - Sales
      - Shrinkage
    It returns data on a per-item, per-day basis.  Inventory is valued at cost,
    and sales figures include computed cost-of-goods-sold values.  Values are
    given as floating-point instead of Decimals.

    Other functions should be wrapped around this function to actually make use
    of the computed values in some way, such as writing to a summary table in
    the database or producing a report."""

    if end is None:
        end = datetime.date.today()

    # For each item, a dictionary:
    #   count: number of that item currently in the inventory
    #   cost: total cost basis for all the items
    #   price: cost/count, the average cost per item
    #
    # Invariants:
    #   cost >= 0.00
    #   cost == 0.00 if count <= 0
    #   price >= 0.00
    inventory = {}

    # Look for an item price from near the start of the period, for computing
    # the initial inventory value.
    cursor.execute("""SELECT i.bulk_type_id,
                             (cost_taxable * (1 + o.tax_rate)
                               + cost_nontaxable) / quantity
                      FROM orders o JOIN order_items i ON (o.id = i.order_id)
                      WHERE o.date < %s
                      ORDER BY o.date DESC""", (start,))
    price_estimates = {}
    for (bulkid, price) in cursor.fetchall():
        if bulkid not in price_estimates: price_estimates[bulkid] = float(price)

    for (k, v) in Inventory.get_inventory_summary(start - ONE_DAY,
                                                  True).items():
        check_item(inventory, k, price_estimates)
        inventory[k]['count'] = v['estimate']
        if v['estimate'] > 0:
            inventory[k]['cost'] = v['estimate'] * inventory[k]['price']
        else:
            inventory[k]['cost'] = 0.0
        yield {'t': 'initial', 'date': start, 'item': k,
               'count': inventory[k]['count'],
               'value': inventory[k]['cost']}

    cursor.execute("""SELECT date, bulkid, SUM(quantity), SUM(price)
                      FROM aggregate_purchases
                      WHERE date >= %s AND date <= %s
                      GROUP BY date, bulkid
                      ORDER BY date""", (start, end))
    sales = cursor.fetchall()

    cursor.execute("""SELECT o.date, i.bulk_type_id, i.quantity * i.number,
                             i.number * (cost_taxable * (1 + o.tax_rate)
                                          + cost_nontaxable)
                      FROM orders o JOIN order_items i ON (o.id = i.order_id)
                      WHERE o.date >= %s AND o.date <= %s
                      ORDER BY o.date""", (start, end))
    purchases = cursor.fetchall()

    cursor.execute("""SELECT date, bulkid, units
                      FROM inventory2
                      WHERE date >= %s AND date <= %s
                      ORDER BY date""", (start, end))
    inventories = cursor.fetchall()

    date = start
    while date <= end:
        updated = set()

        for p in extract(purchases, date):
            (_, bulkid, count, cost) = p
            if bulkid is None: continue
            cost = float(cost)
            check_item(inventory, bulkid, price_estimates)
            inv = inventory[bulkid]

            # Special case when the starting inventory was negative, since we
            # were accounting for negative items at zero cost.
            if inv['count'] < 0:
                cost = cost * (inv['count'] + count) / count
                cost = max(cost, 0.0)

            inv['count'] += count
            inv['cost'] += cost
            updated.add(bulkid)

            yield {'t': 'receive', 'date': date, 'item': bulkid,
                   'count': count, 'value': cost}

        for s in extract(sales, date):
            (_, bulkid, count, cost) = s
            if bulkid is None: continue
            cost = float(cost)
            check_item(inventory, bulkid, price_estimates)
            inv = inventory[bulkid]
            if inv['count'] == 0:
                cogs = 0.0
            elif count == inv['count']:
                cogs = inv['cost']
            else:
                cogs = min(inv['cost'], count * (inv['cost'] / inv['count']))
            inv['cost'] -= cogs
            inv['count'] -= count
            updated.add(bulkid)

            yield {'t': 'sell', 'date': date, 'item': bulkid,
                   'count': -count, 'value': -cogs, 'income': cost}

        for bulkid in updated:
            inv = inventory[bulkid]
            if inv['count'] > 0:
                inv['price'] = inv['cost'] / inv['count']
            assert inv['cost'] >= 0.0
            assert inv['price'] >= 0.0
            if inv['count'] <= 0: assert inv['cost'] == 0.0

        for i in extract(inventories, date):
            (_, bulkid, count) = i
            check_item(inventory, bulkid, price_estimates)
            inv = inventory[bulkid]
            if count != inv['count']:
                assert count >= 0
                qty = inv['count'] - count
                newcost = inv['price'] * count
                costchange = newcost - inv['cost']
                inv['count'] = count
                inv['cost'] = newcost

                yield {'t': 'shrinkage', 'date': date, 'item': bulkid,
                       'count': -qty, 'value': costchange}

        date += ONE_DAY

@django.db.transaction.commit_manually
def summary(start, end=None, commit_start=None):
    date = None
    losses = 0.0
    inventory_value = 0.0

    def commit_day():
        cursor.execute("""SELECT value FROM finance_inventory_summary
                          WHERE date=%s""",
                       (date,))
        old_value = Decimal("0.00")
        for r in cursor.fetchall():
            old_value = r[0]

        if date == commit_start:
            print "--- COMMITTING ---"

        print "%s: inventory=%.2f shrinkage=%.2f [old_value=%s delta=%s]" \
            % (date, inventory_value, losses,
               old_value, to_decimal(inventory_value) - old_value)

        if commit_day is not None and date < commit_start:
            return

        cursor.execute("DELETE FROM finance_inventory_summary WHERE date=%s",
                       (date,))
        cursor.execute("""INSERT INTO
                            finance_inventory_summary(date, value, shrinkage)
                          VALUES (%s, %s, %s)""",
                       (date, to_decimal(inventory_value), to_decimal(losses)))

    print "Gathering price data..."
    first_result_seen = False
    for inv in generate_inventory_report(start, end):
        if not first_result_seen:
            print "Summarizing inventory data..."
            first_result_seen = True

        if inv['date'] != date:
            if date is not None: commit_day()
            date = inv['date']
            losses = 0.0

        inventory_value += inv['value']
        if inv['t'] == 'shrinkage':
            print "  LOSS: $%.02f (%d) %s" \
                % (-inv['value'], -inv['count'],
                   BulkItem.objects.get(bulkid=inv['item']).description)
            losses -= inv['value']

    commit_day()
    django.db.transaction.commit()

def report_inventory(start, end=None):
    """Compute a summary of inventory values and shrinkage."""

    value = 0.0
    shrinkage = 0.0
    profit = 0.0
    last_date = None

    for inv in generate_inventory_report(start, end):
        if inv['date'] != last_date:
            print "%s: value=%.2f, shrinkage=%.2f profit=%.2f" % \
                (last_date, value, shrinkage, profit)
            last_date = inv['date']
            shrinkage = 0.0
            profit = 0.0

        value += inv['value']
        if inv['t'] == 'shrinkage':
            shrinkage += -inv['value']
        elif inv['t'] == 'sell':
            profit += inv['income'] + inv['value']

    print "%s: value=%.2f, shrinkage=%.2f profit=%.2f" % \
        (last_date, value, shrinkage, profit)

def item_report(start, end=None):
    """Compute a per-item summary of shrinkage and sales."""

    value = 0.0
    shrinkage = 0.0
    profit = 0.0
    last_date = None

    items = {}

    for inv in generate_inventory_report(start, end):
        id = inv['item']
        if id not in items:
            items[id] = {'sales': 0.0, 'shrinkage': 0.0, 'cost': 0.0}

        if inv['t'] == 'sell':
            items[id]['sales'] += inv['income']
            items[id]['cost'] += -inv['value']
        elif inv['t'] == 'shrinkage':
            items[id]['shrinkage'] += -inv['value']

    (sales, shrinkage, cost) = (0.0, 0.0, 0.0)
    print "Item\tLocation\tSales\tCost\tShrinkage"
    for id in items:
        if not sum(abs(items[id][k]) for k in ('sales', 'shrinkage', 'cost')):
            continue
        bulk = BulkItem.objects.get(bulkid=id)
        print "%s\t%d\t%.2f\t%.2f\t%.2f" % \
            (bulk.description, bulk.floor_location, items[id]['sales'],
             items[id]['cost'], items[id]['shrinkage'])
        sales += items[id]['sales']
        shrinkage += items[id]['shrinkage']
        cost += items[id]['cost']

def category_report(start, end=None):
    """Compute a per-category summary of shrinkage and sales.
       
    This should be used to compute necessary per-category markups to cover
    losses."""

    groups = {}

    def category(id, category_cache={}):
        if id not in category_cache:
            bulk = BulkItem.objects.get(bulkid=id)
            category_cache[id] = bulk.floor_location.name
        return category_cache[id]

    for inv in generate_inventory_report(start, end):
        g = category(inv['item'])
        if g not in groups:
            groups[g] = {'sales': 0.0, 'shrinkage': 0.0, 'cost': 0.0}

        if inv['t'] == 'sell':
            groups[g]['sales'] += inv['income']
            groups[g]['cost'] += -inv['value']
        elif inv['t'] == 'shrinkage':
            groups[g]['shrinkage'] += -inv['value']

    for g in sorted(groups.keys()):
        print "%s:" % (g,)
        i = groups[g]
        for k in ('sales', 'cost', 'shrinkage'):
            print "    %s = %.2f" % (k, i[k])
        print "    profit = %.2f" % (i['sales'] - i['cost'] - i['shrinkage'],)
        try:
            print "    loss_pct = %.2f%%" % \
                (i['shrinkage'] / (i['shrinkage'] + i['cost']) * 100.0,)
        except ZeroDivisionError:
            pass