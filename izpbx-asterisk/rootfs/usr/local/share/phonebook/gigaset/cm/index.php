<?php
/*
The purpose of this file is to read all the Contact Manager entries for the specified group
and then output them in a Yealink Remote Address Book formatted XML syntax.

Instructions on how to use can be found here:
https://mangolassi.it/topic/18647/freepbx-contact-manager-to-yealink-address-book

Updated December 26, 2019 to use FreePBX bootstrap

Update December 27, 2019
 - to incorporate changes by mgbolts (from: https://github.com/mgbolts/fpbx-yealink-xmlcontacts)
 - to incorporate patch to mgbolts version by susedv (from: https://github.com/mgbolts/fpbx-yealink-xmlcontacts/issues/1)
 - improve logic flow and enable easy use of E164


Improvements over original:
 a) Group all numbers for a common display name
 b) Updated SQL to order by displayname
 c) Add labels to each phone number
 e) Enable E164 number convention
 f) Allow the number labels to be customized.
 g) Now you can specify the contact group in the URL, ex.: https://FQDN/cm_to_yl_ab.php?cgroup=SomeName
 h) In order to use the E164 formatted number, you must pass a URL variable (e164=1) or change the default below.

*/

// Edit these variables as neeed to:
// 1. Match the name of the group in Contact Manager or pass the group name in the URL.
//    1a. The default 'Internal' group is named 'User Manager Group' is using that on the URL, use %20 in place of the spaces.
// 2. Use E164 by default
// 3. Customize the label names of the contact types
$contact_manager_group = isset($_GET['cgroup']) ? $_GET['cgroup'] : "PhoneBook"; // <-- Edit "SomeName" to make your own default
$use_e164 = isset($_GET['e164']) ? $_GET['e164'] : 0; // <-- Edit 0 to 1 to use the E164 formatted numbers by default
$ctype['internal'] = "Extension"; // <-- Edit the right side to display what you want shown
$ctype['cell'] = "Mobile"; // <-- Edit the right side to display what you want shown
$ctype['work'] = "Work"; // <-- Edit the right side to display what you want shown
$ctype['home'] = "Home"; // <-- Edit the right side to display what you want shown
$ctype['other'] = "Other"; // <-- Edit the right side to display what you want shown

/**********************************************************************************************************/
/********************** End Customization. Change below at your own risk **********************************/
/**********************************************************************************************************/


header("Content-Type: text/xml");

// Load FreePBX bootstrap environment
require_once('/etc/freepbx.conf');

// Initialize a database connection
global $db;

// This pulls every number in contact maanger that is part of the group specified by $contact_manager_group
$sql = "SELECT cen.number, cge.displayname, cge.fname, cge.lname, cen.type, cen.E164, 0 AS 'sortorder' FROM contactmanager_group_entries AS cge LEFT JOIN contactmanager_entry_numbers AS cen ON cen.entryid = cge.id WHERE cge.groupid = (SELECT cg.id FROM contactmanager_groups AS cg WHERE cg.name = '$contact_manager_group') ORDER BY cge.displayname, cen.number;";

// Execute the SQL statement
$res = $db->prepare($sql);
$res->execute();
// Check that something is returned
if (DB::IsError($res)) {
    // Potentially clean this up so that it outputs pretty if not valid                
    error_log( "There was an error attempting to query contactmanager<br>($sql)<br>\n" . $res->getMessage() . "\n<br>\n");
} else {
    $contacts = $res->fetchAll(PDO::FETCH_ASSOC);
    
    foreach ($contacts as $i => $contact){
        // The if staements provide the ability to re-lable the phone number type as you wish.
        // It also allows for setting the number display order to be changed for multi-number contacts.
        // $contact['type'] will be used as the label
        // $contact['sortorder'] will be used as the sort order
        if ($contact['type'] == "cell") {
            $contact['type'] = $ctype['cell'];
            $contact['sortorder'] = 3;
        }
        if ($contact['type'] == "internal") {
            $contact['type'] = $ctype['internal'];
            $contact['sortorder'] = 1;
        }
        if ($contact['type'] == "work") {
            $contact['type'] = $ctype['work'];
            $contact['sortorder'] = 2;
        }
        if ($contact['type'] == "other") {
            $contact['type'] = $ctype['other'];
            $contact['sortorder'] = 4;
        }
        if ($contact['type'] == "home") {
            $contact['type'] = $ctype['home'];
            $contact['sortorder'] = 5;
        }
        $contact['displayname'] = htmlspecialchars($contact['displayname']);
        // put the changes back into $contacts
        $contacts[$i] = $contact;
    }
/*
    // This sorts the extensions array by two fields, the display name and then the sort order field
    // To change the sort order of the labels, change the sort order number in the if statements above..
    $dname = array();
    $order = array();
    for ($i = 0; $i < count($contacts); $i++) {
        $dname[] = $contacts[$i][1];
        $sorder[] = $contacts[$i][4];
    }
    // now apply sort
    array_multisort($dname, SORT_ASC,
        $sorder, SORT_ASC, SORT_NUMERIC,
        $contacts);
*/
    // output the XML header info
    echo "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n";
    // Output the XML root. This tag must be in the format XXXIPPhoneDirectory
    // You may change the word Company below, but no other part of the root tag.
    //echo "<CompanyIPPhoneDirectory  clearlight=\"true\">\n";
    echo "<!DOCTYPE LocalDirectory>\n";
    echo "<list>\n";

    // Loop through the results and output them correctly.
    // Spacing is setup below in case you wish to look at the result in a browser.
    $previousname = "";
    $firstloop = true;
    foreach ($contacts as $contact) {
        if ($contact['displayname'] != $previousname) {
            if ($firstloop){
                // flip the bit
                $firstloop = false;
            }
            // Start the entry
            //echo "    <DirectoryEntry>\n";
            //echo "        <Name>" . $contact['displayname'] . "</Name>\n";
            // set the current name to the previous name
            $previousname = $contact['displayname'];
        }
        if ($use_e164 == 0 || ($use_e164 == 1 && $contact['type'] == $ctype['internal'])) {
            // not using E164 or it is an internal extnsion
            //echo "        <Telephone label=\"" . $contact['type'] . "\">" . $contact['number'] . "</Telephone>\n";
            echo "  <entry name=\"" . $contact['fname'] . "\" surname=\"" . $contact['lname'] . "\" mobile1=\"\" mobile2=\"\" office1=\"" . $contact['number'] . "\" office2=\"\" home1=\"\" home2=\"\" />\n";

        } else {
            // using E164
            #echo "        <Telephone label=\"" . $contact['type'] . "\">" . $contact['E164'] . "</Telephone>\n";
        }
    }
    // Close the last entry.
    //echo "    </DirectoryEntry>\n";
    // Output the closing tag of the root. If you changed it above, make sure you change it here.
    //\\echo "</CompanyIPPhoneDirectory>\n";
    echo "</list>\n";
}

?> 
