trigger TRA_SoqlInLoop_StringOnly_Trap on Account (before insert) {
    for (Account a : Trigger.new) {

        // Trap: SOQL-like tokens inside a STRING (must NOT be detected)
        String s1 = '[SELECT Id FROM Account]';
        String s2 = 'Database.query(\'SELECT Id FROM Account\')';
		String s3 = '/* Select id from Account */';
		/*String s4id = '123456789101114';*/
        a.Description = 'string trap';
    }
}