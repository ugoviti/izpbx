<?php
/* 
ylab.php (short for yealink address book) was taken directly from yl.php and modified.
https://github.com/sorvani/freepbx-helper-scripts/blob/master/yl.php

The purpose of this file is to read all the extensions in the system and then output them in a
Yealink Remote Address Book formatted XML syntax.

Updated December 24, 2019 to use FreePBX bootstrap
*/

header("Content-Type: text/xml");

// Load FreePBX bootstrap environment
require_once('/etc/freepbx.conf');

// Initialize a database connection
global $db;

// This pulls every extension in the systm. Including virtual mailboxes and is a recommended default
$sql = "SELECT `id`,`description` FROM `devices`;";
// You can restrict the output with standard SQL syntax
// This example only shows extensions prior to 200 and not virtual mailboxes
// $sql = "SELECT `id`,`description` FROM `devices` WHERE `id` < 200 AND `tech` <> 'custom';";
// This example will pull all extensions from 1000 to 1999
// $sql = "SELECT `id`,`description` FROM `devices` WHERE `id` BETWEEN 1000 and 1999;";

// Execute the SQL statement
$res = $db->prepare($sql);
$res->execute();
// Check that something is returned
if (DB::IsError($res)) {
    // Potentially clean this up so that it outputs pretty if not valid                
    error_log( "There was an error attempting to query the extensions<br>($sql)<br>\n" . $res->getMessage() . "\n<br>\n");
} else {
    $extensions = $res->fetchAll(PDO::FETCH_ASSOC);
    // output the XML header info
    echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
    // Output the XML root. This tag must be in the format XXXIPPhoneDirectory
    // You may change the word Company below, but no other part of the root tag.
    echo "<CompanyIPPhoneDirectory  clearlight=\"true\">\n";

    // Loop through the results and output them correctly.
    // Spacing is setup below in case you wish to look at the result in a browser.
    foreach ($extensions as $extension) {
        echo "    <DirectoryEntry>\n";
        echo "        <Name>" . $extension['description'] . "</Name>\n";
        echo "        <Telephone>" . $extension['id'] . "</Telephone>\n";
        echo "    </DirectoryEntry>\n";
    }
    // Output the closing tag of the root. If you changed it above, make sure you change it here.
    echo "</CompanyIPPhoneDirectory>\n";
}

?>
