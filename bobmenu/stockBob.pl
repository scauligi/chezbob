#!/usr/bin/perl -w

### libraries and constants
use Pg;
$DLG = "/usr/bin/dialog";

###############################################################################
# stockBob.pl
#
# DESCRIPTION:
# Perl script that offers a quick way to insert new products
# and update the inventory of existing products.
# This specific module/program does not allow the change of pricing or naming
# of an existing product.
###############################################################################


###############################################################################
# SUBROUTINES
###############################################################################


sub
isa_barcode
{
    my ($rawInput) = @_;
    if ($rawInput =~ /^\.C/)
    {
	my @getParsed = split /\./,$rawInput;
	my $numToken = @getParsed;
	if ($numToken == 4) {
	    return 1;
	}
    }
    return 0;
}

sub
decode_barcode {
    my ($rawInput) = @_;

    # this skips the barcode type stuff.
    my @getParsed = split /\./,$rawInput;
    my $rawBarcode = $getParsed[3];
    $rawBarcode =~ tr/a-zA-Z0-9+-/ -_/;
    $rawBarcode = unpack 'u', chr(32 + length($rawBarcode) * 3/4) 
	. $rawBarcode;
    $rawBarcode =~ s/\0+$//;
    $rawBarcode ^= "C" x length($rawBarcode);
    return $rawBarcode;
}


########################################
# verifyAndDecodeAnyBarcode - takses any barcode whether cuecat or
#character and verifies it. Only returns barcode that detects 12 digits
#or 8 digits.
########################################
sub
verifyAndDecodeAnyBarcode
{
    my ($guess) = @_;    
    if (&isa_barcode($guess)) {
	$guess = &decode_barcode($guess);
    }
    if (($guess =~/^\d{12}$/) || ($guess =~ /^\d{7}$/)) {
	return $guess;
    }
    else {
	# Bad input
	return "";
    }
}


########################################
# errorBarcode
########################################
sub
errorBarcode
{
  my $win_title = "Bad Barcode";
  my $win_text = "The input was not recognized as a valid barcode";

  system("$DLG --title \"$win_title\" --clear --msgbox \"" .
	 $win_text .
	 "\" 6 55 2> /dev/null");
  # check the number and insert it into database.
}


########################################
# newProduct_win
########################################
sub
newProduct_win
{
# Long subroutine - keeps track of all the new variables that can
# be entered in this lenghty process of entering new products.
# Breaking this subroutine into smaller ones would just require more
# parameter passing around or reqiure state saving from the main program.

  my ($conn, $newBarcode) = @_;
  my $flag = 1;
  my $newName = "";
  my $newPhonetic_Name = "";
  my $newPrice = "";
  my $newStock = "";

  # ASK FOR NEW NAME FOR NEW PRODUCT
  my $win_title = "New Product";
  my $win_text = " The barcode to this product is not in the database." .
      "This is a new product. Please enter the name of this product.";
  while ($newName !~ /\w+/) {
      if (system("$DLG --title \"$win_title\" --clear --inputbox \"" .
		 $win_text .
		 "\" 12 55 2> /tmp/input.product") != 0) {
	  return "";
      }
      $newName = `cat /tmp/input.product`;
      system("rm -f /tmp/input.product");
  }

  # ASK FOR PHONETIC NAME
  $win_title = "Phonetic Name For $newName";
  $win_text = " Please enter a PHONETIC NAME for the Speech Synthesis.";
  while ($newPhonetic_Name !~ /\w+/) {
      if (system("$DLG --title \"$win_title\" --clear --inputbox \"" .
		 $win_text .
		 "\" 12 55 2> /tmp/input.product") != 0) {
	  return "";
      }
      $newPhonetic_Name = `cat /tmp/input.product`;
      system("rm -f /tmp/input.product");
      # check for proper input and then ask for quantity for stock.  
  }

  # ASK FOR PRICE
  $win_title = "Enter the PRICE of $newName";
  $win_text = "Please enter the PRICE of this item (include decimal point for cents).";
  while ($newPrice !~ /^\d*\.\d{0,2}$/) {
      if (system("$DLG --title \"$win_title\" --clear --inputbox \"" .
		 $win_text .
		 "\" 8 55 2> /tmp/input.product") != 0) {
	  return "";
      }      
      $newPrice = `cat /tmp/input.product`;
      system("rm -f /tmp/input.product");      
  }

  while ($newStock !~ /^\d+$/) {
      $win_title = "Enter the STOCK of $newName";
      $win_text = "Please enter the amount in stock.";
      
      if (system("$DLG --title \"$win_title\" --clear --inputbox \"" .
		 $win_text .
		 "\" 8 55 2> /tmp/input.product") != 0) {
	  return "";
      }
      $newStock = `cat /tmp/input.product`;
      system("rm -f /tmp/input.product");
  }
  
  my $insertqueryFormat = q{
      insert into products
	  values(
		 '%s',
		 '%s',
		 '%s',
		 %.2f,
		 %d
		 );
  };

  my $result = $conn->exec(sprintf($insertqueryFormat,				   
				   $newBarcode,
				   $newName,
				   $newPhonetic_Name,
				   $newPrice,
				   $newStock));
  if ($result->resultStatus != PGRES_COMMAND_OK) {
      print STDERR "add_win: error inserting record...exiting\n";
      exit 1;
  }
  $win_title = "New Product Entered into Database";
  $win_text = "The following product has been entered:\n"
      ."Name: $newName\nPrice:$newPrice\nStock:$newStock";
  system("$DLG --title \"$win_title\" --clear --msgbox \"" .
	 $win_text .
	 "\" 9 55");
  # may want to add speech here to test the voice synthesis name
}

sub
newBulk_win
{
  my ($conn, $newBarcode) = @_;
  my $newName = "";

  # ASK FOR NEW NAME FOR NEW PRODUCT
  my $win_title = "New Bulk Product";
  my $win_text = " The barcode of this bulk item is not in the database." .
      "Please enter the name of this product.";
  while ($newName !~ /\w+/) {
      if (system("$DLG --title \"$win_title\" --clear --inputbox \"" .
		 $win_text .
		 "\" 12 55 2> /tmp/input.product") != 0) {
	  return "";
      }
      $newName = `cat /tmp/input.product`;
      system("rm -f /tmp/input.product");
  }

  # ASK FOR Number of kinds of items in the bulk item
  $win_title = "# of kinds"; 
  $win_text = "Enter the number of kinds of items";
  while (system("$DLG --title \"$win_title\" --clear --inputbox \"" .
		 $win_text .
		 "\" 8 55 2> /tmp/input.product") != 0) {} 
  $numKinds = `cat /tmp/input.product`;
  system("rm -f /tmp/input.product");      

  # for each kind, get the barcode and quantity and record in db
  for ($i=1; $i<=$numKinds; $i++) {
    $win_title = "product $i";
    $win_text = "Scan the barcode of product $i"; 
    my $done = 0;
    while (!$done) {
      system("$DLG --title \"$win_title\" --clear --inputbox \"" .
		 $win_text .
		 "\" 8 55 2> /tmp/input.product"); 
      $guess = `cat /tmp/input.product`;
      system("rm -f /tmp/input.product");      
      $prodbarcode = &verifyAndDecodeAnyBarcode($guess);
      if($prodbarcode eq "") {
        &errorBarcode();
      } else {
        $done = 1;
      }
    } 

    $win_text = "Enter the quantity of product $i"; 
    while (system("$DLG --title \"$win_title\" --clear --inputbox \"" .
		 $win_text .
		 "\" 8 55 2> /tmp/input.product") != 0) {}
    $quan = `cat /tmp/input.product`;
    system("rm -f /tmp/input.product");      

    my $insertqueryFormat = q{
      insert into bulk_items
	  values(
		 '%s',
		 '%s',
		 '%s',
		 %d
		 );
    };
    my $result = $conn->exec(sprintf($insertqueryFormat,
  				   $newBarcode,
  				   $newName,
  				   $prodbarcode,
				   $quan));
    if ($result->resultStatus != PGRES_COMMAND_OK) {
        print STDERR "add_win: error inserting record...exiting\n";
        exit 1;
    }
  }
}


########################################
# oldProduct_win
########################################
sub
oldProduct_win
{
  my ($conn, $newBarcode, $name, $phonetic_name, $price, $stock) = @_;
  my $win_title = "$name";
  my $win_text = "Product Name: $name.\n".
      " Present TOTALS STOCK: $stock\n".
      " Please enter a number to add to the present stock total\n".
      " (Enter negative number to subtract from present total):\n";

  if (system("$DLG --title \"$win_title\" --clear --inputbox \"" .
	     $win_text .
	     "\" 14 55 2> /tmp/input.product") != 0) {
      return "";
  }

  my $newStock = `cat /tmp/input.product`;
  system("rm -rf /tmp/input.product");

  $newStock = $newStock + $stock;

  # check the number and update the database.
  my $updatequeryFormat = q{
      update products
	  set stock = %d
	      where barcode = '%s';
  };

  my $result = $conn->exec(sprintf($updatequeryFormat,
				   $newStock,
				   $newBarcode));
  if ($result->resultStatus != PGRES_COMMAND_OK) {
      print STDERR "add_win: error updating record...exiting\n";
      exit 1;
  }
  $win_title = "Stock Updated";
  $win_text = "You have updated the stock to a new total of $newStock.";
  system("$DLG --title \"$win_title\" --clear --msgbox \"" .
	 $win_text .
	 "\" 8 55");
}


########################################
# enterBarcode
########################################
sub
enterBarcode
{
    my ($conn) = @_;
    my $guess = "0";
    my $newBarcode = "0";
    
    my $win_title = "Stock Manager: Enter Barcode";
    my $win_text = "Enter the barcode of a product";
    
    while (1) {
	if (system("$DLG --title \"$win_title\" --clear --inputbox \"" .
		   $win_text .
		   "\" 8 55 2> /tmp/input.barcode") != 0) {
	    return "";
	}
	
	$guess = `cat /tmp/input.barcode`;
	system("rm -f /tmp/input.barcode");

	$newBarcode = &verifyAndDecodeAnyBarcode($guess);

	if($newBarcode eq "") {
	    # case where barcode is not a barcode...
	    &errorBarcode();
	} else {
	    my $selectqueryFormat = q{
		select *
	        from products
		where barcode = '%s';
	    };
	    my $result = $conn->exec(sprintf($selectqueryFormat, 
					     $newBarcode));
	    if ($result->ntuples == 1) {
		# assign each value in DB to a perl variable.
		$newBarcode = $result->getvalue(0,0);
		my $name = $result->getvalue(0,1);
		my $phonetic_name = $result->getvalue(0,2);
		my $price = $result->getvalue(0,3);
		my $stock  = $result->getvalue(0,4);
		&oldProduct_win($conn,
				$newBarcode,
				$name,
				$phonetic_name,
				$price,
				$stock);
	    } else {
		# product not found... enter new product;
		&newProduct_win($conn, $newBarcode);
	    }
	}
    }
}

sub
enterBulkBarcode
{
    my ($conn) = @_;
    my $guess = "0";
    my $newBarcode = "0";
    
    my $win_title = "Stock Manager: Enter Barcode";
    my $win_text = "Enter the barcode of a product";
    
    while (1) {
	if (system("$DLG --title \"$win_title\" --clear --inputbox \"" .
		   $win_text .
		   "\" 8 55 2> /tmp/input.barcode") != 0) {
	    return "";
	}
	
	$guess = `cat /tmp/input.barcode`;
	system("rm -f /tmp/input.barcode");

	$newBarcode = &verifyAndDecodeAnyBarcode($guess);

	if($newBarcode eq "") {
	    # case where barcode is not a barcode...
	    &errorBarcode();
	} else {
	    my $selectqueryFormat = q{
		select *
	        from bulk_items
		where bulk_barcode = '%s';
	    };
	    my $result = $conn->exec(sprintf($selectqueryFormat, 
					     $newBarcode));
	    if ($result->ntuples != 0) {
              for ($i=0; $i<$result->ntuples; $i++) {
                my $updatequeryFormat = q{
                  update products 
                  set stock = stock + %d
                  where barcode = '%s';
                };
	        my $rv = $conn->exec(sprintf($updatequeryFormat, 
					     $result->getvalue($i,3),
               				     $result->getvalue($i,2)));
  		if ($rv->resultStatus != PGRES_COMMAND_OK) {
	           print STDERR "bulk: error update record...exiting\n";
                   exit 1;
                }
              }
              my $bulkname = $result->getvalue(0,1);
	      system("$DLG --msgbox \"$bulkname update complete\" 8 30"); 
                
	    } else {
		# product not found... enter new product;
		&newBulk_win($conn, $newBarcode);
	    }
	}
    }
}

########################################
########################################
# deleteProduct
########################################
sub
deleteProduct
{
    my ($conn) = @_;
    my $guess = "0";
    my $newBarcode = "0";
    
    my $win_title = "Stock Manager: Delete Product";
    my $win_text = "Enter the barcode of the product you want to DELETE.";

    while (1) {
	if (system("$DLG --title \"$win_title\" --clear --inputbox \"" .
		   $win_text .
		   "\" 8 55 2> /tmp/input.barcode") != 0) {
	    return "";
	}
	
	$guess = `cat /tmp/input.barcode`;
	system("rm -f /tmp/input.barcode");
	
	$newBarcode = &verifyAndDecodeAnyBarcode($guess);
	
	if($newBarcode eq "") {
	    # case where barcode is not a barcode...
	    &errorBarcode();
	} else {
	    # Confirm deletion by showing the item in a confirmation dialog box.

	    # First get the name of the item
	    my $selectqueryFormat = q{
		select name
		    from products
			where barcode = '%s';
	    };
	    my $result = $conn->exec(sprintf($selectqueryFormat, $newBarcode));
	    $win_title = "Barcode Not Found";
	    $win_text = "Barcode not found in database.";
	    if ($result->ntuples != 1) {
		system("$DLG --title \"$win_title\" --clear --msgbox \"" .
		       $win_text .
		       "\" 8 55");
		return"";
	    }

	    my $newName = $result->getvalue(0,0);
	    # Then create the confirmation box
	    $win_title = "Confirm the Deletion of: $newName";
	    $win_text = "DELETE $newName?"; 
	    if (system("$DLG --title \"$win_title\" --clear --yesno \"" .
		       $win_text .
		       "\" 8 55") != 0) {
		return "";
	    }

	    my $deletequeryFormat = q{
		delete
		    from products
			where barcode = '%s';
			};
	    $result = $conn->exec(sprintf($deletequeryFormat,
					  $newBarcode));
	    if ($result->resultStatus != PGRES_COMMAND_OK) {
		print STDERR "delete_win: error deleting record...exiting\n";
		exit 1;
	    }
	    $win_title = "Deleted $newName";
	    $win_text = "You have just deleted $newName from the database.";
	    system("$DLG --title \"$win_title\" --clear --msgbox \"" .
		       $win_text .
		   "\" 8 55");
	    return "";
	}
    }
}


########################################
# ChangeName
########################################
sub
changeName
{
    my ($conn) = @_;
    my $guess = "0";
    my $newBarcode = "0";
    
    my $win_title = "Stock Manager: Change Name";
    my $win_text = "Enter the barcode of the product you want to change the NAME of.";

    while (1) {
	if (system("$DLG --title \"$win_title\" --clear --inputbox \"" .
		   $win_text .
		   "\" 8 55 2> /tmp/input.barcode") != 0) {
	    return "";
	}
	
	$guess = `cat /tmp/input.barcode`;
	system("rm -f /tmp/input.barcode");
	
	$newBarcode = &verifyAndDecodeAnyBarcode($guess);
	
	if($newBarcode eq "") {
	    # case where barcode is not a barcode...
	    &errorBarcode();
	} else {
	    # Confirm deletion by showing the item in a confirmation dialog box.

	    # First get the name of the item
	    my $selectqueryFormat = q{
		select name
		    from products
			where barcode = '%s';
	    };
	    my $result = $conn->exec(sprintf($selectqueryFormat, $newBarcode));
	    $win_title = "Barcode Not Found";
	    $win_text = "Barcode not found in database.";
	    if ($result->ntuples != 1) {
		system("$DLG --title \"$win_title\" --clear --msgbox \"" .
		       $win_text .
		       "\" 8 55");
		return"";
	    }	    

	    my $name = $result->getvalue(0,0);
	    # Then create the confirmation box
	    $win_title = "Changing the Name of $name";
	    $win_text = "Change the NAME from $name to what?"; 
	    if (system("$DLG --title \"$win_title\" --clear --inputbox \"" .
		       $win_text .
		       "\" 8 55 2> /tmp/input.name") != 0) {
		return "";
	    }	    

	    my $newName = `cat /tmp/input.name`;
	    system("rm -rf /tmp/input.name");

	    my $updatequeryFormat = q{
		update products
		    set name = '%s'
			where barcode = '%s';
	    };
	    $result = $conn->exec(sprintf($updatequeryFormat,
					  $newName,
					  $newBarcode));
	    if ($result->resultStatus != PGRES_COMMAND_OK) {
		print STDERR "update_win: error deleting record...exiting\n";
		exit 1;
	    }
	    $win_title = "Changed $name to $newName";
	    $win_text = "Changed the name from:\n$name => $newName";

	    system("$DLG --title \"$win_title\" --clear --msgbox \"" .
		   $win_text .
		   "\" 8 55");
	    return "";
	}
    }
}


########################################
# ChangePrice
########################################
sub
changePrice
{
    my ($conn) = @_;
    my $guess = "0";
    my $newBarcode = "0";
    
    my $win_title = "Stock Manager: Change PRICE";
    my $win_text = "Enter the barcode of the product you want to change".
	"the PRICE of.";

    while (1) {
	if (system("$DLG --title \"$win_title\" --clear --inputbox \"" .
		   $win_text .
		   "\" 8 55 2> /tmp/input.barcode") != 0) {
	    return "";
	}
	
	$guess = `cat /tmp/input.barcode`;
	system("rm -f /tmp/input.barcode");
	
	$newBarcode = &verifyAndDecodeAnyBarcode($guess);
	
	if($newBarcode eq "") {
	    # case where barcode is not a barcode...
	    &errorBarcode();
	} else {
	    # Confirm deletion by showing the item in a confirmation dialog box.

	    # First get the name of the item
	    my $selectqueryFormat = q{
		select name, price 
		    from products
			where barcode = '%s';
	    };
	    my $result = $conn->exec(sprintf($selectqueryFormat, $newBarcode));
	    $win_title = "Barcode Not Found";
	    $win_text = "Barcode not found in database.";
	    if ($result->ntuples != 1) {
		system("$DLG --title \"$win_title\" --clear --msgbox \"" .
		       $win_text .
		       "\" 8 55");
		return"";
	    }	    

	    my $name = $result->getvalue(0,0);
	    my $price = $result->getvalue(0,1);
	    # Then create the confirmation box
	    $win_title = "Changing the PRICE of $name";
	    $win_text = "Change the PRICE of $name from $price to what?\n".
		"(include decimals for cents)"; 

	    my $newPrice = "";
	    do {
		if (system("$DLG --title \"$win_title\" --clear --inputbox \"" .
			   $win_text .
			   "\" 8 55 2> /tmp/input.name") != 0) {
		    return "";
		}	    
		
		$newPrice = `cat /tmp/input.name`;
		system("rm -rf /tmp/input.name");
	    } while ($newPrice !~ /^\d*\.\d{0,2}$/);

	    my $updatequeryFormat = q{
		update products
		    set price = '%s'
			where barcode = '%s';
	    };
	    $result = $conn->exec(sprintf($updatequeryFormat,
					  $newPrice,
					  $newBarcode));
	    if ($result->resultStatus != PGRES_COMMAND_OK) {
		print STDERR "update_win: error deleting record...exiting\n";
		exit 1;
	    }
	    $win_title = "Changed the PRICE of $name";
	    $win_text = "Changed the PRICE of $name from:\n$price => $newPrice";

	    system("$DLG --title \"$win_title\" --clear --msgbox \"" .
		   $win_text .
		   "\" 8 55");
	    return "";
	}
    }
}


########################################
# ChangePhonetics
########################################
sub
changePhonetics
{
    my ($conn) = @_;
    my $guess = "0";
    my $newBarcode = "0";
    
    my $win_title = "Stock Manager: Change PHONETICS";
    my $win_text = "Enter the barcode of the product you want to change".
	"the PHONETICS of.";

    while (1) {
	if (system("$DLG --title \"$win_title\" --clear --inputbox \"" .
		   $win_text .
		   "\" 8 55 2> /tmp/input.barcode") != 0) {
	    return "";
	}
	
	$guess = `cat /tmp/input.barcode`;
	system("rm -f /tmp/input.barcode");
	
	$newBarcode = &verifyAndDecodeAnyBarcode($guess);
	
	if($newBarcode eq "") {
	    # case where barcode is not a barcode...
	    &errorBarcode();
	} else {
	    # Confirm deletion by showing the item in a confirmation dialog box.

	    # First get the name of the item
	    my $selectqueryFormat = q{
		select name, phonetic_name
		    from products
			where barcode = '%s';
	    };
	    my $result = $conn->exec(sprintf($selectqueryFormat, $newBarcode));
	    $win_title = "Barcode Not Found";
	    $win_text = "Barcode not found in database.";
	    if ($result->ntuples != 1) {
		system("$DLG --title \"$win_title\" --clear --msgbox \"" .
		       $win_text .
		       "\" 8 55");
		return"";
	    }	    

	    my $name = $result->getvalue(0,0);
	    my $phonetic_name = $result->getvalue(0,1);
	    # Then create the confirmation box
	    $win_title = "Changing the PHONETICS of $name";
	    $win_text = "Change the PHONETICS of $name from $phonetic_name to what?\n";

	    my $newPhonetic_Name = "";
	    do {
		if (system("$DLG --title \"$win_title\" --clear --inputbox \"" .
			   $win_text .
			   "\" 8 55 2> /tmp/input.name") != 0) {
		    return "";
		}	    
		
		$newPhonetic_Name = `cat /tmp/input.name`;
		system("rm -rf /tmp/input.name");
	    } while ($newPhonetic_Name !~ /\w+/);

	    my $updatequeryFormat = q{
		update products
		    set phonetic_name = '%s'
			where barcode = '%s';
	    };
	    $result = $conn->exec(sprintf($updatequeryFormat,
					  $newPhonetic_Name,
					  $newBarcode));
	    if ($result->resultStatus != PGRES_COMMAND_OK) {
		print STDERR "update_win: error deleting record...exiting\n";
		exit 1;
	    }
	    $win_title = "Changed the PHONETICS of $name";
	    $win_text = "Changed the PHONETICS of $name from:\n$phonetic_name"
		." => $newPhonetic_Name";

	    system("$DLG --title \"$win_title\" --clear --msgbox \"" .
		   $win_text .
		   "\" 8 55");
	    return "";
	}
    }
}


########################################
# mainMenu - the big front menu
########################################
sub
mainMenu
{
    my $win_title = "Chez Bob Inventory Manager";
    my $win_textFormat = "Welcome to Chez Bob Inventory Management System.";

    my $retval =
	system("$DLG --title \"$win_title\" --clear --menu \"" .
	       "$win_textFormat".
	       "\" 14 70 8 " .
	       "\"Restock Bulk\" " .
	       "\"Restock products in bulk\" " .
	       "\"Restock Item\" " .
	       "\"Restock an individual product \" " .
	       "\"Change Price\" " .
	       "\"Change the PRICE of a product \" " .
	       "\"Change Name\" " .
	       "\"Change the NAME of a product \" " .
	       "\"Change Phonetics\" " .
	       "\"Change the PHONETIC name of a product \" " .
	       "\"Delete\" " .
	       "\"DELETE a product \" " .
	       "\"Inventory\" " .
	       "\"Turn inventory system on or off \" " .
	       "\"Quit\" " .
	       "\"QUIT this program\" " .
	       " 2> /tmp/input.action");
    
    my $action = `cat /tmp/input.action`;
    system("rm -f /tmp/input.*");
    if ($action eq "")
    {
	$action = "Quit";
    }
    return $action;
}


###############################################################################
# MAIN PROGRAM
###############################################################################

$conn = Pg::connectdb("dbname=bob");
if ($conn->status == PGRES_CONNECTION_BAD) {
    print STDERR "MAIN: error connecting to database...exiting.\n";
    print STDERR $conn->errorMessage;
    exit 1;
}

$action = "";

while ($action ne "Quit") {
    $action = &mainMenu();

    if ($action eq "Delete") {
	&deleteProduct($conn);
    }
    elsif ($action eq "Restock Bulk") {
	&enterBulkBarcode($conn);
    }
    elsif ($action eq "Restock Item") {
	&enterBarcode($conn);
    }
    elsif ($action eq "Change Name") {
	&changeName($conn);
    }
    elsif ($action eq "Change Price") {
	&changePrice($conn);
    }
    elsif ($action eq "Change Phonetics") {
	&changePhonetics($conn);
    }
    elsif ($action eq "Inventory") {
	
    }
}