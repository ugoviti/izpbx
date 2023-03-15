#!/usr/bin/env php
<?php
/*------------------------------------------------------------------------------
 autoband.php
*/

/*------------------------------------------------------------------------------
 Initiate logging and load dependencies.
*/
openlog("autoband", LOG_PID|LOG_CONS|LOG_PERROR, LOG_LOCAL0);
require_once 'error.inc';
require_once 'ami.class.inc';
require_once 'autoban.class.inc';

/*------------------------------------------------------------------------------
 Define AMI event handlers.
*/
function eventAbuse($event,$parameters,$server,$port) {
	global $ban;
	if (array_key_exists('RemoteAddress',$parameters)) {
		$address = explode('/',$parameters['RemoteAddress']);
		$ip = $address[2];
		if (!empty($ip)) {
			$ban->book($ip);
		}
	}
}

/*------------------------------------------------------------------------------
 Create class objects and set log level.
*/
$ban = new \Autoban('/etc/asterisk/autoban.conf');
$ami = new \PHPAMI\Ami('/etc/asterisk/autoban.conf');
$ami->setLogLevel(2);

/*------------------------------------------------------------------------------
 Register the AMI event handlers to their corresponding events.
*/
$ami->addEventHandler('FailedACL',               'eventAbuse');
$ami->addEventHandler('InvalidAccountID',        'eventAbuse');
$ami->addEventHandler('ChallengeResponseFailed', 'eventAbuse');
$ami->addEventHandler('InvalidPassword',         'eventAbuse');

/*------------------------------------------------------------------------------
 Start code execution.
 Wait 1s allowing Asterisk time to setup the Asterisk Management Interface (AMI).
 If autoban is activated try to connect to the AMI. If successful, start
 listening for events indefinitely. If connection fails, retry to connect.
 If autoban is deactivated stay in an infinite loop instead of exiting.
 Otherwise the system supervisor will relentlessly just try to restart us.
*/

define("MAX_WAIT_RETRIES",10);

$wait_init  = 5; // 5secs to try to connect
$wait_extra = 55; // wait 55secs after failed attempt
$wait_retries = MAX_WAIT_RETRIES;
$wait_off   = 3600;
if ($ban->config['autoban']['enabled']) {
	while($wait_retries--) {
		sleep($wait_init);
		if ($ami->connect()) {
			trigger_error('Activated and connected to AMI',E_USER_NOTICE);
			$ami->waitResponse(); // listen for events until connection fails
			$ami->disconnect();
			$wait_retries=MAX_WAIT_RETRIES; // reload wait retry counter after every successful connect
		} else {
			trigger_error('Unable to connect to AMI',E_USER_ERROR);
			sleep($wait_extra);
		}
	}
	trigger_error('MAX_WAIT_RETRIES exceeded. Giving up finally.',E_USER_ERROR);
} else {
	trigger_error('Disabled! Activate autoban using conf file '.
	'(/etc/asterisk/autoban.conf)',E_USER_NOTICE);
	while($ban->config['autoban']['stayalive']) { sleep($wait_off); }
}


/*------------------------------------------------------------------------------
 We will never come here.
*/
?>
