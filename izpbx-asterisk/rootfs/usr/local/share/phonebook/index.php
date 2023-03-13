<?php

// Load FreePBX bootstrap environment
require_once('/etc/freepbx.conf');

// Initialize a database connection
global $db;
$sql = "SELECT * FROM asterisk.contactmanager_groups WHERE id !='1'";


$BOOK=$_GET["pb"];
$PHONE=$_GET["phone"];

// Execute the SQL statement
$res = $db->prepare($sql);
$res->execute();


if ($PHONE == ""){
  if (DB::IsError($res)) {
    // Potentially clean this up so that it outputs pretty if not valid
    error_log( "There was an error attempting to query the extensions<br>($sql)<br>\n" . $res->getMessage() . "\n<br>\n");
  }else{
    echo "izPBX supported Phonebooks:<br><br>";
    echo "- <a href=".$_SERVER['QUERY_STRING']."?phone=yealink>Yealink / Fanvil</a><br>";
    echo "- <a href=".$_SERVER['QUERY_STRING']."?phone=gigaset>Gigaset</a><br>";
  }
}else{
    echo "Selected Phone: <b>".$_GET["phone"]."</b><br>";
    echo "Available Address Books: <br>";
    //echo "- <a href=".$PHONE.".php?pb=ext>Extensions</a><br>";
    echo "- <a href=".$PHONE."/ext>Extensions</a><br>";

    $client = $res->fetchAll(PDO::FETCH_ASSOC);
    foreach ($client as $client) {
      #echo "- <a href=".$PHONE.".php?pb=".$client["name"].">".$client["name"]."</a><br>";
      echo "- <a href=".$PHONE."/".$client["name"].">".$client["name"]."</a><br>";
    }
}

if (($PHONE != '')&&($BOOK != '')){
    if ($PHONE == 'yealink'){
      include $PHONE.".php";
    }elseif ($PHONE == 'gigaset'){
      include $PHONE.".php";
    }else{
        echo "empty";
    }
}

// SVUOTO LE VARIABILI
$_SERVER['REQUEST_URI']="";
$BOOK=$_GET[""];
$PHONE=$_GET[""];
?>

