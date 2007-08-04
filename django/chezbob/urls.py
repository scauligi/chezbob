from django.conf.urls.defaults import *

urlpatterns = patterns('',
    # Default admin interface for editing database
    (r'^admin/', include('django.contrib.admin.urls')),

    (r'^products/$', 'chezbob.bobdb.views.products'),
    (r'^products/([0-9]+)/$', 'chezbob.bobdb.views.product_detail'),

    (r'^orders/([0-9]+)/$', 'chezbob.bobdb.views.view_order'),
    (r'^orders/([0-9]+)/update/$', 'chezbob.bobdb.views.update_order'),

    (r'^inventory/$', 'chezbob.bobdb.views.inventory'),
    (r'^inventory/([0-9]+)/$', 'chezbob.bobdb.views.inventory_detail'),
)
