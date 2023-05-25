#define MYSQL_CHARSET "utf8mb4"

bool DBLoaded;
Database DB;
bool SQLite;

stock void DB_Query(SQLQueryCallback callback, any data = 0, DBPriority prio = DBPrio_Normal, const char[] format_query, any ...)
{
	int len = strlen(format_query) + 512;
	char[] szQuery = new char [len];
	VFormat(szQuery, len, format_query, 5);
	DB.Query(callback, szQuery, data, prio);
}

void DatabaseConnect()
{
	if(SQL_CheckConfig("entwatch"))
	{
		Database.Connect(ConnectCallBack, "entwatch", 0);
	}
	else
	{
		char buffer[256];
		DB = SQLite_UseDatabase("entwatch", buffer, 256);
		ConnectCallBack(DB, buffer, 1);
	}
}

public void ConnectCallBack(Database db, const char[] error, int data)
{
	if (db == null)
	{
		SetFailState("Database failure: %s", error);
		return;
	}
	DB = db;
		
	if(data == 1)
	{
		char buffer[16];
		DBDriver hDBDriver = DB.Driver;
		hDBDriver.GetIdentifier(buffer, sizeof(buffer));
		
		if (!strcmp(buffer, "mysql", false))
		{
			SQLite = false;
		}
		else if (!strcmp(buffer, "sqlite", false))
		{
			SQLite = true;
		}
		else
		{
			SetFailState("ConnectCallBack: Driver \"%s\" is not supported!", buffer);
		}
	}
	else
	{
		SQLite = true;
	}
		
	if(SQLite)
	{
		DB.Query(SQL_Callback_CreateTables, "CREATE TABLE IF NOT EXISTS `ebans` (\
																`pid` INTEGER NOT NULL,\
																`pname` VARCHAR(32) NOT NULL default 'unknown',\
																`pip` VARCHAR(16) NOT NULL default 'unknown',\
																`aid` INTEGER NOT NULL default '0',\
																`aname` VARCHAR(32) NOT NULL default 'unknown',\
																`duration` INTEGER UNSIGNED NOT NULL,\
																`expires` INTEGER UNSIGNED NOT NULL);");
		
	}
	else
	{
		DB.Query(SQL_Callback_CheckError, "SET NAMES '" ... MYSQL_CHARSET ... "'");
		DB.Query(SQL_Callback_CheckError, "SET CHARSET '" ... MYSQL_CHARSET ... "'");
		DB.SetCharset(MYSQL_CHARSET);
		
		DB.Query(SQL_Callback_CreateTables, "CREATE TABLE IF NOT EXISTS `ebans` (\
																`pid` int NOT NULL,\
																`pname` varchar(32) NOT NULL default 'unknown',\
																`pip` varchar(16) NOT NULL default 'unknown',\
																`aid` int NOT NULL default '0',\
																`aname` varchar(32) NOT NULL default 'unknown',\
																`duration` int unsigned NOT NULL,\
																`expires` int unsigned NOT NULL\
																) DEFAULT CHARSET=" ... MYSQL_CHARSET ... ";");
	}
							  
		
	DB.SetCharset("utf8");
}

public void SQL_Callback_CreateTables(Database hDatabase, DBResultSet results, const char[] error, int iData)
{
	if(error[0])
	{
		LogError("SQL_Callback_CreateTables: %s", error);
		return;
	}
	
	DBLoaded = true;

	APIOnDatabaseLoaded();
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
		{
			ClientAuth(i);
		}
	}
}

public void SQL_Callback_CheckError(Database hDatabase, DBResultSet results, const char[] error, int iData)
{
	if(error[0])
	{
		LogError("SQL_Callback_CheckError: %s", error);
		return;
	}
}