#include "surftimer/db/queries.sp"

/*==================================
=          DATABASE SETUP          =
==================================*/

public void db_setupDatabase()
{
	/*===================================
	=    INIT CONNECTION TO DATABASE    =
	===================================*/
	if (!SQL_CheckConfig("surftimer"))
	{
		SetFailState("[SurfTimer] Can not find the \"surftimer\" entry in your \"addons/sourcemod/configs/databases.cfg\" config.");
		return;
	}

	Database.Connect(OnConnect, "surftimer");
}

public void OnConnect(Database db, const char[] error, any data)
{
	if (db == null || strlen(error))
	{
		SetFailState("[SurfTimer] Unable to connect to database (%s)", error);
		return;
	}

	g_dDb = db;

	char szIdent[8];
	g_dDb.Driver.GetIdentifier(szIdent, sizeof(szIdent));

	if (strcmp(szIdent, "mysql", false) == 0)
	{
		// https://github.com/nikooo777/ckSurf/pull/58
		g_dDb.Query(sqlSetSQLMode, "SET sql_mode=(SELECT REPLACE(@@sql_mode,'ONLY_FULL_GROUP_BY',''));", _, DBPrio_Low);
	}
	else
	{
		SetFailState("[SurfTimer] Invalid database type");
		return;
	}
}

public void sqlSetSQLMode(Database db, DBResultSet results, const char[] error, any data)
{
	if (db == null || strlen(error))
	{
		LogError("[surftimer] SQL Error (sqlSetSQLMode): %s", error);
		return;
	}

	// If updating from a previous version
	if (!g_dDb.SetCharset("utf8mb4"))
	{
		SetFailState("[SurfTimer] Can not set charset to \"utf8mb4\". Upgrade your mysql server to a version with support for \"utf8mb4\".");
		return;
	}

	db_createTables();
}

public void db_createTables()
{
	Transaction tTransaction = new Transaction();

	tTransaction.AddQuery(sql_createPlayertmp, 1);
	tTransaction.AddQuery(sql_createPlayertimes, 2);
	tTransaction.AddQuery("SELECT COUNT(1) FROM INFORMATION_SCHEMA.STATISTICS WHERE table_schema=DATABASE() AND table_name='ck_playertimes' AND index_name='maprank';", 3);
	tTransaction.AddQuery(sql_createPlayerRank, 4);
	tTransaction.AddQuery(sql_createPlayerOptions, 5);
	tTransaction.AddQuery(sql_createLatestRecords, 6);
	tTransaction.AddQuery(sql_createBonus, 7);
	tTransaction.AddQuery("SELECT COUNT(1) FROM INFORMATION_SCHEMA.STATISTICS WHERE table_schema=DATABASE() AND table_name='ck_bonus' AND index_name='bonusrank';", 8);
	tTransaction.AddQuery(sql_createCheckpoints, 9);
	tTransaction.AddQuery(sql_createZones, 10);
	tTransaction.AddQuery(sql_createMapTier, 11);
	tTransaction.AddQuery(sql_createSpawnLocations, 12);
	tTransaction.AddQuery(sql_createAnnouncements, 13);
	tTransaction.AddQuery(sql_createVipAdmins, 14);
	tTransaction.AddQuery(sql_createWrcps, 15);

	g_dDb.Execute(tTransaction, SQLTxn_CreateDatabaseSuccess, SQLTxn_CreateDatabaseFailed);
}

public void SQLTxn_CreateDatabaseSuccess(Handle db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	for (int i = 0; i < numQueries; i++)
	{
		if (queryData[i] == 3 || queryData[i] == 8)
		{
			if (results[i].HasResults && results[i].FetchRow())
			{
				if (results[i].FetchInt(0) == 0)
				{
					if (queryData[i] == 3)
					{
						g_dDb.Query(sqlcreatePlayertimesIndex, sql_createPlayertimesIndex, _, DBPrio_Low);
					}
					else
					{
						g_dDb.Query(sqlcreateBonusIndex, sql_createBonusIndex, _, DBPrio_Low);
					}
				}
			}
		}
	}

	CreateTimer(2.0, Timer_Init);
}

public Action Timer_Init(Handle timer)
{
	db_present();
	db_viewMapSettings();

	/// Start Loading Server Settings
	ConVar cvHibernateWhenEmpty = FindConVar("sv_hibernate_when_empty");

	if ((IsServerProcessing() || !cvHibernateWhenEmpty.BoolValue))
	{
		LogToFileEx(g_szLogFile, "[surftimer] Starting to load server settings");
		g_fServerLoading[0] = GetGameTime();
		db_selectMapZones();
	}

	db_selectBonusCount();

	if (GetConVarBool(g_hDBMapcycle))
		db_selectMapCycle();
	else if (!GetConVarBool(g_hMultiServerMapcycle))
		readMapycycle();
	else
		readMultiServerMapcycle();
}

public void SQLTxn_CreateDatabaseFailed(Handle db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	SetFailState("[SurfTimer] Database tables could not be created! Error (Query: %d): %s", queryData[failIndex], error);
}

/* Admin Delete Menu */
public void sql_DeleteMenuView(Database db, DBResultSet results, const char[] error, int serial)
{
	int client = GetClientFromSerial(serial);
	
	Menu editing = new Menu(callback_DeleteRecord);
	editing.SetTitle("%s Records Editing Menu - %s\n► Editing %s record\n► Press the menu item to delete the record\n ", g_szMenuPrefix, g_EditingMap[client], g_EditTypes[g_SelectedEditOption[client]]);
	
	char menuFormat[88];
	FormatEx(menuFormat, sizeof(menuFormat), "Style: %s\n► Press the menu item to change the style\n ", g_EditStyles[g_SelectedStyle[client]]);
	editing.AddItem("0", menuFormat);
	
	if(g_SelectedEditOption[client] > 0)
	{
		FormatEx(menuFormat, sizeof(menuFormat), "%s: %i\n► Press the menu item to change the %s\n ", g_SelectedEditOption[client] == 1 ? "Stage":"Bonus", g_SelectedType[client], g_SelectedEditOption[client] == 1 ? "stage":"bonus");
		editing.AddItem("0", menuFormat);
	}
	
	if (!IsValidDatabase(db, error))
	{
		PrintToServer("Error %s", error);
	}
	else if (!results.RowCount)
	{
		editing.AddItem("1", "No records found", ITEMDRAW_DISABLED);
		editing.Display(client, MENU_TIME_FOREVER);
	}
	else
	{
		char playerName[32], steamID[32];
		float runTime;
		char menuFormatz[128];
		int i = 0;
		while (results.FetchRow())
		{
			i++;
			results.FetchString(0, steamID, 32);
			results.FetchString(1, playerName, 32);
			runTime = results.FetchFloat(2);
			char szRunTime[128];
			FormatTimeFloat(client, runTime, 3, szRunTime, sizeof(szRunTime));
			FormatEx(menuFormat, sizeof(menuFormat), "Rank: %d ► %s - %s", i, playerName, szRunTime);
			ReplaceString(playerName, 32, ";;;", ""); // make sure the client dont has this in their name.
			
			FormatEx(menuFormatz, 128, "%s;;;%s;;;%s", playerName, steamID, szRunTime);
			editing.AddItem(menuFormatz, menuFormat);
		}
		editing.Display(client, MENU_TIME_FOREVER);
	}
}

public int callback_DeleteRecord(Menu menu, MenuAction action, int client, int key)
{
	if(action == MenuAction_Select)
	{
		if(key == 0)
		{
			if(g_SelectedStyle[client] < MAX_STYLES - 1)
				g_SelectedStyle[client]++;
			else
				g_SelectedStyle[client] = 0;
			
			char szQuery[512];
			
			switch(g_SelectedEditOption[client])
			{
				case 0:
				{
					FormatEx(szQuery, 512, sql_MainEditQuery, "runtimepro", "ck_playertimes", g_EditingMap[client], g_SelectedStyle[client], "", "runtimepro");
				}
				case 1:
				{
					char stageQuery[32];
					FormatEx(stageQuery, 32, "AND stage='%i' ", g_SelectedType[client]);
					FormatEx(szQuery, 512, sql_MainEditQuery, "runtimepro", "ck_wrcps", g_EditingMap[client], g_SelectedStyle[client], stageQuery, "runtimepro");
				}
				case 2:
				{
					char stageQuery[32];
					FormatEx(stageQuery, 32, "AND zonegroup='%i' ", g_SelectedType[client]);
					FormatEx(szQuery, 512, sql_MainEditQuery, "runtime", "ck_bonus", g_EditingMap[client], g_SelectedStyle[client], stageQuery, "runtime");
				}
			}
		
			
			if (g_cLogQueries.BoolValue)
			{
				LogToFile(g_szQueryFile, "callback_DeleteRecord - szQuery: %s", szQuery);
			}
			g_dDb.Query(sql_DeleteMenuView, szQuery, GetClientSerial(client), DBPrio_Low);
			return 0;
		}
	
		if(g_SelectedEditOption[client] > 0 && key == 1)
		{
			g_iWaitingForResponse[client] = 6;
			CPrintToChat(client, "%t", "DeleteRecordsNewValue", g_szChatPrefix);
			return 0;
		}
	
		
		char menuItem[128];
		menu.GetItem(key, menuItem, 128);
		
		char recordsBreak[3][32];
		ExplodeString(menuItem, ";;;", recordsBreak, sizeof(recordsBreak), sizeof(recordsBreak[]));
		
		Menu confirm = new Menu(callback_Confirm);

		confirm.SetTitle("%s Records Editing Menu - Confirm Deletion\n► Deleting %s [%s] %s record\n ", g_szMenuPrefix, recordsBreak[0], recordsBreak[1], recordsBreak[2]);

		confirm.AddItem("0", "No");
		confirm.AddItem(recordsBreak[1], "Yes\n \n► This cannot be undone");

		if (GetConVarBool(g_drDeleteSecurity))
			confirm.Display(client, MENU_TIME_FOREVER);
		else
			callback_Confirm(confirm, MenuAction_Select, client, 1);

		return 0;
	}
	else if (action == MenuAction_Cancel)
	{
		if (key == MenuCancel_Exit)
			ShowMainDeleteMenu(client);
	}
	else if(action == MenuAction_End)
		delete menu;
		
	return 0;
}

public int callback_Confirm(Menu menu, MenuAction action, int client, int key)
{
	if(action == MenuAction_Select)
	{
		if(key == 1)
		{
			char steamID[32];
			menu.GetItem(key, steamID, 32);
			
			char szQuery[512], szQuerySelect[512];

			Handle pack = CreateDataPack();
			WritePackString(pack, steamID);
			
			switch(g_SelectedEditOption[client])
			{
				case 0:
				{
					WritePackString(pack, "");
					WritePackCell(pack, 0);

					FormatEx(szQuery, 512, sql_MainDeleteQeury, "ck_playertimes", g_EditingMap[client], g_SelectedStyle[client], steamID, "");
					FormatEx(szQuerySelect, 512, sql_selectMapRecordDeletion, "runtimepro", "ck_playertimes", g_EditingMap[client], g_SelectedStyle[client], "runtimepro", "");
				}
				case 1:
				{
					WritePackString(pack, "stage");
					WritePackCell(pack, g_SelectedType[client]);

					char stageQuery[32];
					FormatEx(stageQuery, 32, "AND stage='%i'", g_SelectedType[client]);
					FormatEx(szQuery, 512, sql_MainDeleteQeury, "ck_wrcps", g_EditingMap[client], g_SelectedStyle[client], steamID, stageQuery);
					FormatEx(szQuerySelect, 512, sql_selectMapRecordDeletion, "runtimepro", "ck_wrcps", g_EditingMap[client], g_SelectedStyle[client], "runtimepro", stageQuery);
				}
				case 2:
				{
					WritePackString(pack, "bonus");
					WritePackCell(pack, g_SelectedType[client]);

					char zoneQuery[32];
					FormatEx(zoneQuery, 32, "AND zonegroup='%i'", g_SelectedType[client]);
					FormatEx(szQuery, 512, sql_MainDeleteQeury, "ck_bonus", g_EditingMap[client], g_SelectedStyle[client], steamID, zoneQuery);
					FormatEx(szQuerySelect, 512, sql_selectMapRecordDeletion, "runtime", "ck_bonus", g_EditingMap[client], g_SelectedStyle[client], "runtime", zoneQuery);
				}
			}
      
			if (g_cLogQueries.BoolValue)
			{
				LogToFile(g_szQueryFile, "callback_Confirm - szQuerySelect: %s", szQuerySelect);
			}
			g_dDb.Query(db_selectMapCurrentWR, szQuerySelect, pack, DBPrio_High);
			if (g_cLogQueries.BoolValue)
			{
				LogToFile(g_szQueryFile, "callback_Confirm - szQuery: %s", szQuery);
			}
			g_dDb.Query(SQL_CheckCallback, szQuery, _, DBPrio_Low);
			
			// Looking for online player to refresh his record after deleting it.
			char player_steamID[32];
			for(int i=1; i <= MaxClients; i++)
			{
				if (!IsValidClient(i) || IsFakeClient(client))
					continue;
					
				GetClientAuthId(i, AuthId_Steam2, player_steamID, 32, true);
				if(StrEqual(player_steamID,steamID))
				{
					g_bSettingsLoaded[client] = false;
					g_bLoadingSettings[client] = true;
					g_iSettingToLoad[client] = 0;
					LoadClientSetting(client, g_iSettingToLoad[client]);
					break;
				}
			}
			
			db_GetMapRecord_Pro();
			
			CPrintToChat(client, "%t", "DeleteRecordsDeletion", g_szChatPrefix);
			ShowMainDeleteMenu(client);
		}

	}
	else if(action == MenuAction_End)
		delete menu;
}


/*==================================
=          SPAWN LOCATION          =
==================================*/

public void db_deleteSpawnLocations(int zGrp, int teleside)
{
	g_bGotSpawnLocation[zGrp][1][teleside] = false;
	char szQuery[128];
	Format(szQuery, sizeof(szQuery), sql_deleteSpawnLocations, g_szMapName, zGrp, teleside);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_deleteSpawnLocations - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_CheckCallback, szQuery, _, DBPrio_Low);
}


public void db_updateSpawnLocations(float position[3], float angle[3], float vel[3], int zGrp, int teleside)
{
	char szQuery[512];
	Format(szQuery, sizeof(szQuery), sql_updateSpawnLocations, position[0], position[1], position[2], angle[0], angle[1], angle[2], vel[0], vel[1], vel[2], g_szMapName, zGrp, teleside);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_updateSpawnLocations - szQuery: %s", szQuery);
	}
	g_dDb.Query(db_editSpawnLocationsCallback, szQuery, zGrp, DBPrio_Low);
}

public void db_insertSpawnLocations(float position[3], float angle[3], float vel[3], int zGrp, int teleside)
{
	char szQuery[512];
	Format(szQuery, sizeof(szQuery), sql_insertSpawnLocations, g_szMapName, position[0], position[1], position[2], angle[0], angle[1], angle[2], vel[0], vel[1], vel[2], zGrp, teleside);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_insertSpawnLocations - szQuery: %s", szQuery);
	}
	g_dDb.Query(db_editSpawnLocationsCallback, szQuery, zGrp, DBPrio_Low);
}

public void db_editSpawnLocationsCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_editSpawnLocationsCallback): %s ", error);
		return;
	}
	db_selectSpawnLocations();
}

public void db_selectSpawnLocations()
{
	for (int s = 0; s < CPLIMIT; s++)
	{
		for (int i = 0; i < MAXZONEGROUPS; i++)
		{
			g_bGotSpawnLocation[i][s][0] = false;
			g_bGotSpawnLocation[i][s][1] = false;
		}
	}

	char szQuery[254];
	Format(szQuery, sizeof(szQuery), sql_selectSpawnLocations, g_szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectSpawnLocations - szQuery: %s", szQuery);
	}
	g_dDb.Query(db_selectSpawnLocationsCallback, szQuery, _, DBPrio_Low);
}

public void db_selectSpawnLocationsCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_selectSpawnLocationsCallback): %s ", error);
		if (!g_bServerDataLoaded)
			db_GetDynamicTimelimit();
		return;
	}

	if (results.HasResults)
	{
		while (results.FetchRow())
		{
			int zonegroup = results.FetchInt(10);
			int stage = results.FetchInt(11);
			int teleside = results.FetchInt(12);

			g_bGotSpawnLocation[zonegroup][stage][teleside] = true;
			g_fSpawnLocation[zonegroup][stage][teleside][0] = results.FetchFloat(1);
			g_fSpawnLocation[zonegroup][stage][teleside][1] = results.FetchFloat(2);
			g_fSpawnLocation[zonegroup][stage][teleside][2] = results.FetchFloat(3);
			g_fSpawnAngle[zonegroup][stage][teleside][0] = results.FetchFloat(4);
			g_fSpawnAngle[zonegroup][stage][teleside][1] = results.FetchFloat(5);
			g_fSpawnAngle[zonegroup][stage][teleside][2] = results.FetchFloat(6);
			g_fSpawnVelocity[zonegroup][stage][teleside][0] = results.FetchFloat(7);
			g_fSpawnVelocity[zonegroup][stage][teleside][1] = results.FetchFloat(8);
			g_fSpawnVelocity[zonegroup][stage][teleside][2] = results.FetchFloat(9);
		}
	}

	if (!g_bServerDataLoaded)
		db_GetDynamicTimelimit();
}

/*===================================
=            PLAYER RANK            =
===================================*/

public void db_viewMapProRankCount()
{
	g_MapTimesCount = 0;
	char szQuery[512];
	Format(szQuery, sizeof(szQuery), sql_selectPlayerProCount, g_szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewMapProRankCount - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_selectPlayerProCountCallback, szQuery, _, DBPrio_Low);
}

public void sql_selectPlayerProCountCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_selectPlayerProCountCallback): %s", error);
		if (!g_bServerDataLoaded)
		{
			db_viewFastestBonus();
		}
		return;
	}

	int style;
	int count;
	if (results.HasResults)
	{
		while (results.FetchRow())
		{
			style = results.FetchInt(0);
			count = results.FetchInt(1);
			if (style == 0)
				g_MapTimesCount = count;
			else
				g_StyleMapTimesCount[style] = count;
		}
	}
	else
	{
		g_MapTimesCount = 0;
		for (int i = 1; i < MAX_STYLES; i++)
			g_StyleMapTimesCount[style] = 0;
	}

	if (!g_bServerDataLoaded)
	{
		db_viewFastestBonus();
	}
	return;
}

// Get players rank in current map
public void db_viewMapRankPro(int client)
{
	char szQuery[512];
	if (!IsValidClient(client))
	return;

	// "SELECT COUNT(*) FROM ck_playertimes WHERE runtimepro <= (SELECT runtimepro FROM ck_playertimes WHERE steamid = '%s' AND mapname = '%s' AND runtimepro > -1.0) AND mapname = '%s' AND runtimepro > -1.0";
	Format(szQuery, sizeof(szQuery), sql_selectPlayerRankProTime, g_szSteamID[client], g_szMapName, g_szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewMapRankPro - szQuery: %s", szQuery);
	}
	g_dDb.Query(db_viewMapRankProCallback, szQuery, GetClientUserId(client), DBPrio_Low);
}

public void db_viewMapRankProCallback(Database db, DBResultSet results, const char[] error, any userid)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_viewMapRankProCallback): %s ", error);
	}

	if (results.HasResults && results.FetchRow())
	{
		int client = GetClientOfUserId(userid);
		if (IsValidClient(client))
		{
			g_MapRank[client] = results.FetchInt(0);
		}
	}
}

// Players points have changed in game, make changes in database and recalculate points
public void db_updateStat(int client, int style)
{
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, style);

	char szQuery[512];
	// "UPDATE ck_playerrank SET finishedmaps ='%i', finishedmapspro='%i', multiplier ='%i'  where steamid='%s'";
	Format(szQuery, sizeof(szQuery), sql_updatePlayerRank, g_pr_finishedmaps[client], g_pr_finishedmaps[client], g_szSteamID[client], style);

	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_updateStat - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_UpdateStatCallback, szQuery, pack, DBPrio_Low);

}

public void SQL_UpdateStatCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_UpdateStatCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int style = ReadPackCell(pack);
	delete pack;

	// Calculating starts here:
	if (IsValidClient(client))
	{
		CalculatePlayerRank(client, style);
	}
}

public void RecalcPlayerRank(int client, char steamid[128])
{
	int i = 66;
	while (g_bProfileRecalc[i] == true)
	i++;
	if (!g_bProfileRecalc[i])
	{
		char szQuery[255];
		char szsteamid[128 * 2 + 1];
		g_dDb.Escape(steamid, szsteamid, 128 * 2 + 1);
		Format(g_pr_szSteamID[i], 32, "%s", steamid);
		Format(szQuery, sizeof(szQuery), sql_selectPlayerName, szsteamid);
		Handle pack = CreateDataPack();
		WritePackCell(pack, i);
		WritePackCell(pack, GetClientUserId(client));
		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "RecalcPlayerRank - szQuery: %s", szQuery);
		}
		g_dDb.Query(sql_selectPlayerNameCallback, szQuery, pack);
	}
}

//
//  1. Point calculating starts here
// 	There are two ways:
//	- if client > MAXPLAYERS, his rank is being recalculated by an admin
//	- else player has increased his rank = recalculate points
//
void CalculatePlayerRank(int client, int style)
{
	char szQuery[255];

	// Take old points into memory, so at the end you can show how much the points changed
	g_pr_oldpoints[client][style] = g_pr_points[client][style];
	// Initialize point calculatin
	g_pr_points[client][style] = 0;

	// Start fluffys points
	g_Points[client][style][0] = 0; // Map Points
	g_Points[client][style][1] = 0; // Bonus Points
	g_Points[client][style][2] = 0; // Group Points
	g_Points[client][style][3] = 0; // Map WR Points
	g_Points[client][style][4] = 0; // Bonus WR Points
	g_Points[client][style][5] = 0; // Top 10 Points
	g_Points[client][style][6] = 0; // WRCP Points
	g_GroupMaps[client][style] = 0; // Group Maps
	g_Top10Maps[client][style] = 0; // Top 10 Maps
	g_WRs[client][style][0] = 0; // WRs
	g_WRs[client][style][1] = 0; // WRBs
	g_WRs[client][style][2] = 0; // WRCPs

	Handle pack = CreateDataPack();
	WritePackCell(pack, client);
	WritePackCell(pack, style);

	Format(szQuery, sizeof(szQuery), "SELECT name FROM ck_playerrank WHERE steamid = '%s' AND style = '%i';", IsValidClient(client) ? g_szSteamID[client] : g_pr_szSteamID[client], style);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "CalculatePlayerRank - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_CalcuatePlayerRankCallback, szQuery, pack, DBPrio_Low);
}

// 2. See if player exists, insert new player into the database
// Fetched values:
// name
public void sql_CalcuatePlayerRankCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_CalcuatePlayerRankCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = ReadPackCell(pack);
	int style = ReadPackCell(pack);

	if (results.HasResults && results.FetchRow())
	{
		if (IsValidClient(client))
		{
			if (GetClientTime(client) < (GetEngineTime() - g_fMapStartTime))
			{
				db_UpdateLastSeen(client); // Update last seen on server
			}
			g_pr_Calculating[client] = true;
		}
			

		// Next up, calculate bonus points:
		char szQuery[512];
		Format(szQuery, sizeof(szQuery), "SELECT mapname, (SELECT count(1)+1 FROM ck_bonus b WHERE a.mapname=b.mapname AND a.runtime > b.runtime AND a.zonegroup = b.zonegroup AND b.style = %i) AS `rank`, (SELECT count(1) FROM ck_bonus b WHERE a.mapname = b.mapname AND a.zonegroup = b.zonegroup AND b.style = %i) as total FROM ck_bonus a WHERE steamid = '%s' AND style = %i;", style, style, g_pr_szSteamID[client], style);
		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "sql_CalcuatePlayerRankCallback - szQuery: %s", szQuery);
		}
		g_dDb.Query(sql_CountFinishedBonusCallback, szQuery, pack, DBPrio_Low);
	}
	else
	{
		delete pack;
		// Players first time on server
		if (client <= MaxClients)
		{
			g_pr_Calculating[client] = false;
			g_pr_AllPlayers[style]++;

			// Insert player to database
			char szQuery[512];
			char szUName[MAX_NAME_LENGTH];
			char szName[MAX_NAME_LENGTH * 2 + 1];
			
			GetClientName(client, szUName, MAX_NAME_LENGTH);
			g_dDb.Escape(szUName, szName, MAX_NAME_LENGTH * 2 + 1);

			char szSteamId64[64];
			GetClientAuthId(client, AuthId_SteamID64, szSteamId64, MAX_NAME_LENGTH, true);

			// "INSERT INTO ck_playerrank (steamid, name, country) VALUES('%s', '%s', '%s');";
			// No need to continue calculating, as the doesn't have any records.
			Format(szQuery, sizeof(szQuery), sql_insertPlayerRank, g_szSteamID[client], szSteamId64, szName, g_szCountry[client], GetTime(), style);
			if (g_cLogQueries.BoolValue)
			{
				LogToFile(g_szQueryFile, "sql_CalcuatePlayerRankCallback - szQuery: %s", szQuery);
			}
			g_dDb.Query(SQL_InsertPlayerCallBack, szQuery, GetClientUserId(client), DBPrio_Low);

			g_pr_finishedmaps[client][style] = 0;
			g_pr_finishedmaps_perc[client][style] = 0.0;
			g_pr_finishedbonuses[client][style] = 0;
			g_pr_finishedstages[client][style] = 0;
			g_GroupMaps[client][style] = 0; // Group Maps
			g_Top10Maps[client][style] = 0; // Top 10 Maps

			// play time
			g_iPlayTimeAlive[client] = 0;
			g_iPlayTimeSpec[client] = 0;

			CalculatePlayerRank(client, style);
		}
	}
}

//
// 3. Calculate points gained from bonuses
// Fetched values
// mapname, rank, total
//
public void sql_CountFinishedBonusCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_CountFinishedBonusCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = ReadPackCell(pack);
	int style = ReadPackCell(pack);

	char szMap[128], szMapName2[128];
	// int totalplayers
	int rank;
	int finishedbonuses = 0;
	int wrbs = 0;

	if (results.HasResults)
	{
		while (results.FetchRow())
		{
			finishedbonuses++;
			// Total amount of players who have finished the bonus
			rank = results.FetchInt(1);
			results.FetchString(0, szMap, 128);
			for (int i = 0; i < GetArraySize(g_MapList); i++) // Check that the map is in the mapcycle
			{
				GetArrayString(g_MapList, i, szMapName2, sizeof(szMapName2));
				if (StrEqual(szMapName2, szMap, false))
				{
					switch (rank)
					{
						case 1:
						{
							g_pr_points[client][style] += 250;
							g_Points[client][style][4] += 250;
							wrbs++;
						}
						case 2:
						{
							g_pr_points[client][style] += 235;
							g_Points[client][style][1] += 235;
						}
						case 3:
						{
							g_pr_points[client][style] += 220;
							g_Points[client][style][1] += 220;
						}
						case 4:
						{
							g_pr_points[client][style] += 205;
							g_Points[client][style][1] += 205;
						}
						case 5:
						{
							g_pr_points[client][style] += 190;
							g_Points[client][style][1] += 190;
						}
						case 6:
						{
							g_pr_points[client][style] += 175;
							g_Points[client][style][1] += 175;
						}
						case 7:
						{
							g_pr_points[client][style] += 160;
							g_Points[client][style][1] += 160;
						}
						case 8:
						{
							g_pr_points[client][style] += 145;
							g_Points[client][style][1] += 145;
						}
						case 9:
						{
							g_pr_points[client][style] += 130;
							g_Points[client][style][1] += 130;
						}
						case 10:
						{
							g_pr_points[client][style] += 100;
							g_Points[client][style][1] += 100;
						}
						case 11:
						{
							g_pr_points[client][style] += 95;
							g_Points[client][style][1] += 95;
						}
						case 12:
						{
							g_pr_points[client][style] += 90;
							g_Points[client][style][1] += 90;
						}
						case 13:
						{
							g_pr_points[client][style] += 80;
							g_Points[client][style][1] += 80;
						}
						case 14:
						{
							g_pr_points[client][style] += 70;
							g_Points[client][style][1] += 70;
						}
						case 15:
						{
							g_pr_points[client][style] += 60;
							g_Points[client][style][1] += 60;
						}
						case 16:
						{
							g_pr_points[client][style] += 50;
							g_Points[client][style][1] += 50;
						}
						case 17:
						{
							g_pr_points[client][style] += 40;
							g_Points[client][style][1] += 40;
						}
						case 18:
						{
							g_pr_points[client][style] += 30;
							g_Points[client][style][1] += 30;
						}
						case 19:
						{
							g_pr_points[client][style] += 20;
							g_Points[client][style][1] += 20;
						}
						case 20:
						{
							g_pr_points[client][style] += 10;
							g_Points[client][style][1] += 10;
						}
						default:
						{
							g_pr_points[client][style] += 5;
							g_Points[client][style][1] += 5;
						}
					}
					break;
				}
			}
		}
	}

	g_pr_finishedbonuses[client][style] = finishedbonuses;
	g_WRs[client][style][1] = wrbs;
	// Next up: Points from stages
	char szQuery[512];
	Format(szQuery, sizeof(szQuery), "SELECT mapname, stage, (select count(1)+1 from ck_wrcps b where a.mapname=b.mapname and a.runtimepro > b.runtimepro and a.style = b.style and a.stage = b.stage) AS `rank` FROM ck_wrcps a where steamid = '%s' AND style = %i;", g_pr_szSteamID[client], style);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "sql_CountFinishedBonusCallback - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_CountFinishedStagesCallback, szQuery, pack, DBPrio_Low);
	return;
}

//
// 4. Calculate points gained from stages
// Fetched values
// mapname, stage, rank, total
//
public void sql_CountFinishedStagesCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_CountFinishedStagesCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = ReadPackCell(pack);
	int style = ReadPackCell(pack);

	char szMap[128], szMapName2[128];
	int finishedstages = 0;
	int rank;
	int wrcps = 0;

	if (results.HasResults)
	{
		while (results.FetchRow())
		{
			finishedstages++;
			// Total amount of players who have finished the bonus
			results.FetchString(0, szMap, 128);
			rank = results.FetchInt(2);
			for (int i = 0; i < GetArraySize(g_MapList); i++) // Check that the map is in the mapcycle
			{
				GetArrayString(g_MapList, i, szMapName2, sizeof(szMapName2));
				if (StrEqual(szMapName2, szMap, false))
				{
					if (rank == 1)
					{
						wrcps++;
						int wrcpPoints = GetConVarInt(g_hWrcpPoints);
						if (wrcpPoints > 0)
						{
							g_pr_points[client][style] += wrcpPoints;
							g_Points[client][style][6] += wrcpPoints;
						}
					}
					break;
				}
			}
		}
	}

	g_pr_finishedstages[client][style] = finishedstages;
	g_WRs[client][style][2] = wrcps;

	// Next up: Points from maps
	char szQuery[512];
	Format(szQuery, sizeof(szQuery), "SELECT mapname, (select count(1)+1 from ck_playertimes b where a.mapname=b.mapname and a.runtimepro > b.runtimepro AND b.style = %i) AS `rank`, (SELECT count(1) FROM ck_playertimes b WHERE a.mapname = b.mapname AND b.style = %i) as total, (SELECT tier FROM `ck_maptier` b WHERE a.mapname = b.mapname) as tier FROM ck_playertimes a where steamid = '%s' AND style = %i;", style, style, g_pr_szSteamID[client], style);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "sql_CountFinishedStagesCallback - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_CountFinishedMapsCallback, szQuery, pack, DBPrio_Low);
	return;
}

// 5. Count the points gained from regular maps
// Fetching:
// mapname, rank, total, tier
public void sql_CountFinishedMapsCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_CountFinishedMapsCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = ReadPackCell(pack);
	int style = ReadPackCell(pack);
	delete pack;

	char szMap[128], szMapName2[128];
	int finishedMaps = 0, totalplayers, rank, tier, wrs;
	if (results.HasResults)
	{
		while (results.FetchRow())
		{
			// Total amount of players who have finished the map
			totalplayers = results.FetchInt(2);
			// Rank in that map
			rank = results.FetchInt(1);
			// Map name
			results.FetchString(0, szMap, 128);
			// Map tier
			tier = results.FetchInt(3);

			for (int i = 0; i < GetArraySize(g_MapList); i++) // Check that the map is in the mapcycle
			{
				GetArrayString(g_MapList, i, szMapName2, sizeof(szMapName2));
				if (StrEqual(szMapName2, szMap, false))
				{
					finishedMaps++;
					float wrpoints;
					int iwrpoints;
					float points;
					float g1points;
					float g2points;
					float g3points;
					float g4points;
					float g5points;

					// Calculate Group Ranks
					// Group 1
					float fG1top;
					int g1top;
					int g1bot = 11;
					fG1top = (float(totalplayers) * g_Group1Pc);
					fG1top += 11.0; // Rank 11 is always End of Group 1
					g1top = RoundToCeil(fG1top);

					int g1difference = (g1top - g1bot);
					if (g1difference < 4)
						g1top = (g1bot + 4);

					// Group 2
					float fG2top;
					int g2top;
					int g2bot;
					g2bot = g1top + 1;
					fG2top = (float(totalplayers) * g_Group2Pc);
					fG2top += 11.0;
					g2top = RoundToCeil(fG2top);

					int g2difference = (g2top - g2bot);
					if (g2difference < 4)
						g2top = (g2bot + 4);

					// Group 3
					float fG3top;
					int g3top;
					int g3bot;
					g3bot = g2top + 1;
					fG3top = (float(totalplayers) * g_Group3Pc);
					fG3top += 11.0;
					g3top = RoundToCeil(fG3top);

					int g3difference = (g3top - g3bot);
					if (g3difference < 4)
						g3top = (g3bot + 4);

					// Group 4
					float fG4top;
					int g4top;
					int g4bot;
					g4bot = g3top + 1;
					fG4top = (float(totalplayers) * g_Group4Pc);
					fG4top += 11.0;
					g4top = RoundToCeil(fG4top);

					int g4difference = (g4top - g4bot);
					if (g4difference < 4)
						g4top = (g4bot + 4);

					// Group 5
					float fG5top;
					int g5top;
					int g5bot;
					g5bot = g4top + 1;
					fG5top = (float(totalplayers) * g_Group5Pc);
					fG5top += 11.0;
					g5top = RoundToCeil(fG5top);

					int g5difference = (g5top - g5bot);
					if (g5difference < 4)
						g5top = (g5bot + 4);

					if (tier == 1)
					{
						wrpoints = ((float(totalplayers) * 1.75) / 6);
						wrpoints += 58.5;
						if (wrpoints < 250.0)
							wrpoints = 250.0;
					}
					else if (tier == 2)
					{
						wrpoints = ((float(totalplayers) * 2.8) / 5);
						wrpoints += 82.15;
						if (wrpoints < 500.0)
							wrpoints = 500.0;
					}
					else if (tier == 3)
					{
						wrpoints = ((float(totalplayers) * 3.5) / 4);
						if (wrpoints < 750.0)
							wrpoints = 750.0;
						else
							wrpoints += 117;
					}
					else if (tier == 4)
					{
						wrpoints = ((float(totalplayers) * 5.74) / 4);
						if (wrpoints < 1000.0)
							wrpoints = 1000.0;
						else
							wrpoints += 164.25;
					}
					else if (tier == 5)
					{
						wrpoints = ((float(totalplayers) * 7) / 4);
						if (wrpoints < 1250.0)
							wrpoints = 1250.0;
						else
							wrpoints += 234;
					}
					else if (tier == 6)
					{
						wrpoints = ((float(totalplayers) * 14) / 4);
						if (wrpoints < 1500.0)
							wrpoints = 1500.0;
						else
							wrpoints += 328;
					}
					else if (tier == 7)
					{
						wrpoints = ((float(totalplayers) * 21) / 4);
						if (wrpoints < 1750.0)
							wrpoints = 1750.0;
						else
							wrpoints += 420;
					}
					else if (tier == 8)
					{
						wrpoints = ((float(totalplayers) * 30) / 4);
						if (wrpoints < 2000.0)
							wrpoints = 2000.0;
						else
							wrpoints += 560;
					}
					else // no tier set
						wrpoints = 25.0;

					// Round WR points up
					iwrpoints = RoundToCeil(wrpoints);

					// Top 10 Points
					if (rank < 11)
					{
						g_Top10Maps[client][style]++;
						if (rank == 1)
						{
							g_pr_points[client][style] += iwrpoints;
							g_Points[client][style][3] += iwrpoints;
							wrs++;
						}
						else if (rank == 2)
						{
							points = (0.80 * iwrpoints);
							g_pr_points[client][style] += RoundToCeil(points);
							g_Points[client][style][5] += RoundToCeil(points);
						}
						else if (rank == 3)
						{
							points = (0.75 * iwrpoints);
							g_pr_points[client][style] += RoundToCeil(points);
							g_Points[client][style][5] += RoundToCeil(points);
						}
						else if (rank == 4)
						{
							points = (0.70 * iwrpoints);
							g_pr_points[client][style] += RoundToCeil(points);
							g_Points[client][style][5] += RoundToCeil(points);
						}
						else if (rank == 5)
						{
							points = (0.65 * iwrpoints);
							g_pr_points[client][style] += RoundToCeil(points);
							g_Points[client][style][5] += RoundToCeil(points);
						}
						else if (rank == 6)
						{
							points = (0.60 * iwrpoints);
							g_pr_points[client][style] += RoundToCeil(points);
							g_Points[client][style][5] += RoundToCeil(points);
						}
						else if (rank == 7)
						{
							points = (0.55 * iwrpoints);
							g_pr_points[client][style] += RoundToCeil(points);
							g_Points[client][style][5] += RoundToCeil(points);
						}
						else if (rank == 8)
						{
							points = (0.50 * iwrpoints);
							g_pr_points[client][style] += RoundToCeil(points);
							g_Points[client][style][5] += RoundToCeil(points);
						}
						else if (rank == 9)
						{
							points = (0.45 * iwrpoints);
							g_pr_points[client][style] += RoundToCeil(points);
							g_Points[client][style][5] += RoundToCeil(points);
						}
						else if (rank == 10)
						{
							points = (0.40 * iwrpoints);
							g_pr_points[client][style] += RoundToCeil(points);
							g_Points[client][style][5] += RoundToCeil(points);
						}
					}
					else if (rank > 10 && rank <= g5top)
					{
						// Group 1-5 Points
						g_GroupMaps[client][style] += 1;
						// Calculate Group Points
						g1points = (iwrpoints * 0.25);
						g2points = (g1points / 1.5);
						g3points = (g2points / 1.5);
						g4points = (g3points / 1.5);
						g5points = (g4points / 1.5);

						if (rank >= g1bot && rank <= g1top) // Group 1
						{
							g_pr_points[client][style] += RoundFloat(g1points);
							g_Points[client][style][2] += RoundFloat(g1points);
						}
						else if (rank >= g2bot && rank <= g2top) // Group 2
						{
							g_pr_points[client][style] += RoundFloat(g2points);
							g_Points[client][style][2] += RoundFloat(g2points);
						}
						else if (rank >= g3bot && rank <= g3top) // Group 3
						{
							g_pr_points[client][style] += RoundFloat(g3points);
							g_Points[client][style][2] += RoundFloat(g3points);
						}
						else if (rank >= g4bot && rank <= g4top) // Group 4
						{
							g_pr_points[client][style] += RoundFloat(g4points);
							g_Points[client][style][2] += RoundFloat(g4points);
						}
						else if (rank >= g5bot && rank <= g5top) // Group 5
						{
							g_pr_points[client][style] += RoundFloat(g5points);
							g_Points[client][style][2] += RoundFloat(g5points);
						}
					}

					// Map Completiton Points
					if (tier == 1)
					{
						g_pr_points[client][style] += 25;
						g_Points[client][style][0] += 25;
					}
					else if (tier == 2)
					{
						g_pr_points[client][style] += 50;
						g_Points[client][style][0] += 50;
					}
					else if (tier == 3)
					{
						g_pr_points[client][style] += 100;
						g_Points[client][style][0] += 100;
					}
					else if (tier == 4)
					{
						g_pr_points[client][style] += 200;
						g_Points[client][style][0] += 200;
					}
					else if (tier == 5)
					{
						g_pr_points[client][style] += 400;
						g_Points[client][style][0] += 400;
					}
					else if (tier == 6)
					{
						g_pr_points[client][style] += 600;
						g_Points[client][style][0] += 600;
					}
					else if (tier == 7)
					{
						g_pr_points[client][style] += 800;
						g_Points[client][style][0] += 800;
					}
					else if (tier == 8)
					{
						g_pr_points[client][style] += 1000;
						g_Points[client][style][0] += 1000;
					}
					else // no tier
					{
						g_pr_points[client][style] += 13;
						g_Points[client][style][0] += 13;
					}
					break;
				}
			}
		}
	}

	// Finished maps amount is stored in memory
	g_pr_finishedmaps[client][style] = finishedMaps;
	// Percentage of maps finished
	g_pr_finishedmaps_perc[client][style] = (float(finishedMaps) / float(g_pr_MapCount[0])) * 100.0;

	// WRs
	g_WRs[client][style][0] = wrs;

	int totalperc = g_pr_finishedstages[client][style] + g_pr_finishedbonuses[client][style] + g_pr_finishedmaps[client][style];
	int totalcomp = g_pr_StageCount + g_pr_BonusCount + g_pr_MapCount[0];
	float ftotalperc;

	ftotalperc = (float(totalperc) / (float(totalcomp))) * 100.0;

	if (IsValidClient(client) && !IsFakeClient(client))
		CS_SetMVPCount(client, (RoundFloat(ftotalperc)));

	// Done checking, update points
	db_updatePoints(client, style);
}

// 6. Updating points to database
public void db_updatePoints(int client, int style)
{
	Handle pack = CreateDataPack();
	WritePackCell(pack, client);
	WritePackCell(pack, style);

	char szQuery[1024];
	char szName[MAX_NAME_LENGTH * 2 + 1];
	char szSteamId[32];

	if (client > MAXPLAYERS && (g_pr_RankingRecalc_InProgress || g_bProfileRecalc[client]))
	{
		g_dDb.Escape(g_pr_szName[client], szName, MAX_NAME_LENGTH * 2 + 1);
		Format(szQuery, sizeof(szQuery), sql_updatePlayerRankPoints, szName, g_pr_points[client][style], g_Points[client][style][3], g_Points[client][style][4], g_Points[client][style][6], g_Points[client][style][5], g_Points[client][style][2], g_Points[client][style][0], g_Points[client][style][1], g_pr_finishedmaps[client][style], g_pr_finishedbonuses[client][style], g_pr_finishedstages[client][style], g_WRs[client][style][0], g_WRs[client][style][1], g_WRs[client][style][2], g_Top10Maps[client][style], g_GroupMaps[client][style], g_pr_szSteamID[client], style);
		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "db_updatePoints - szQuery: %s", szQuery);
		}
		g_dDb.Query(sql_updatePlayerRankPointsCallback, szQuery, pack, DBPrio_Low);
	}
	else if (IsValidClient(client))
	{
		char szName2[MAX_NAME_LENGTH * 2 + 1];
		GetClientName(client, szName, MAX_NAME_LENGTH);
		g_dDb.Escape(szName, szName2, MAX_NAME_LENGTH * 2 + 1);
		GetClientAuthId(client, AuthId_Steam2, szSteamId, MAX_NAME_LENGTH, true);
		Format(szQuery, sizeof(szQuery), sql_updatePlayerRankPoints2, szName2, g_pr_points[client][style], g_Points[client][style][3], g_Points[client][style][4], g_Points[client][style][6], g_Points[client][style][5], g_Points[client][style][2], g_Points[client][style][0], g_Points[client][style][1], g_pr_finishedmaps[client][style], g_pr_finishedbonuses[client][style], g_pr_finishedstages[client][style], g_WRs[client][style][0], g_WRs[client][style][1], g_WRs[client][style][2], g_Top10Maps[client][style], g_GroupMaps[client][style], g_szCountry[client], szSteamId, style);
		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "db_updatePoints - szQuery: %s", szQuery);
		}
		g_dDb.Query(sql_updatePlayerRankPointsCallback, szQuery, pack, DBPrio_Low);
	}
}

// 7. Calculations done, if calculating all, move forward, if not announce changes.
public void sql_updatePlayerRankPointsCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_updatePlayerRankPointsCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = ReadPackCell(pack);
	int style = ReadPackCell(pack);
	delete pack;

	// If was recalculating points, go to the next player, announce or end calculating
	if (client > MAXPLAYERS && (g_pr_RankingRecalc_InProgress || g_bProfileRecalc[client]))
	{
		if (g_bProfileRecalc[client] && !g_pr_RankingRecalc_InProgress)
		{
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsValidClient(i))
				{
					if (StrEqual(g_szSteamID[i], g_pr_szSteamID[client]))
						CalculatePlayerRank(i, 0);
				}
			}
		}

		g_bProfileRecalc[client] = false;
		if (g_pr_RankingRecalc_InProgress)
		{
			// console info
			if (IsValidClient(g_pr_Recalc_AdminID) && g_bManualRecalc)
				PrintToConsole(g_pr_Recalc_AdminID, "%i/%i", g_pr_Recalc_ClientID, g_pr_TableRowCount);

			int x = 66 + g_pr_Recalc_ClientID;
			if (StrContains(g_pr_szSteamID[x], "STEAM", false) != -1)
			{
				ContinueRecalc(x);
			}
			else
			{
				for (int i = 1; i <= MaxClients; i++)
				if (1 <= i <= MaxClients && IsValidEntity(i) && IsValidClient(i))
				{
					if (g_bManualRecalc)
						CPrintToChat(i, "%t", "PrUpdateFinished", g_szChatPrefix);
				}

				g_bManualRecalc = false;
				g_pr_RankingRecalc_InProgress = false;

				if (IsValidClient(g_pr_Recalc_AdminID))
					CreateTimer(0.1, RefreshAdminMenu, GetClientUserId(g_pr_Recalc_AdminID), TIMER_FLAG_NO_MAPCHANGE);
			}
			g_pr_Recalc_ClientID++;
		}
	}
	else // Gaining points normally
	{
		// Player recalculated own points in !profile
		if (g_bRecalcRankInProgess[client] && client <= MAXPLAYERS)
		{
			ProfileMenu2(client, style, "", g_szSteamID[client]);
			if (IsValidClient(client))
			{
				if (style == 0)
					CPrintToChat(client, "%t", "Rc_PlayerRankFinished", g_szChatPrefix, g_pr_points[client][style]);
				else
					CPrintToChat(client, "%t", "Rc_PlayerRankFinished2", g_szChatPrefix, g_szStyleMenuPrint[style], g_pr_points[client][style]);
			}

			g_bRecalcRankInProgess[client] = false;
		}
		if (IsValidClient(client) && g_pr_showmsg[client]) // Player gained points
		{
			char szName[MAX_NAME_LENGTH];
			GetClientName(client, szName, MAX_NAME_LENGTH);

			int diff = g_pr_points[client][style] - g_pr_oldpoints[client][style];
			if (diff > 0) // if player earned points -> Announce
			{
				for (int i = 1; i <= MaxClients; i++)
				{
					if (IsValidClient(i))
					{
						if (style == 0)
							CPrintToChat(i, "%t", "EarnedPoints", g_szChatPrefix, szName, diff, g_pr_points[client][0]);
						else
							CPrintToChat(i, "%t", "EarnedPoints2", g_szChatPrefix, szName, diff, g_szStyleRecordPrint[style], g_pr_points[client][style]);
					}
				}
			}

			g_pr_showmsg[client] = false;
			db_CalculatePlayersCountGreater0(style);
			db_GetPlayerRank(client, style);
			CreateTimer(1.0, SetClanTag, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		}
		g_pr_Calculating[client] = false;
	}
}

// Called when player joins server
public void db_viewPlayerPoints(int client)
{
	for (int i = 0; i < MAX_STYLES; i++)
	{
		g_pr_finishedmaps[client][i] = 0;
		g_pr_finishedmaps_perc[client][i] = 0.0;
		g_pr_points[client][i] = 0;
	}

	if (GetConVarBool(g_hEnforceDefaultTitles))
		LoadDefaultTitle(client);

	g_bPrestigeCheck[client] = false;
	g_bPrestigeAvoid[client] = false;
	
	if (!g_bPrestigeCheck[client]) {
		if (GetConVarBool(g_hPrestigeVip) && (IsPlayerVip(client, false, false) || g_iHasEnforcedTitle[client])) {
			g_bPrestigeCheck[client] = true;
			g_bPrestigeAvoid[client] = true;
		}
	}
	
	g_iPlayTimeAlive[client] = 0;
	g_iPlayTimeSpec[client] = 0;
	g_iTotalConnections[client] = 1;
	char szQuery[255];

	if (!IsValidClient(client))
		return;

	// "SELECT steamid, name, points, finishedmapspro, country, lastseen, timealive, timespec, connections from ck_playerrank where steamid='%s'";
	Format(szQuery, sizeof(szQuery), sql_selectRankedPlayer, g_szSteamID[client]);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewPlayerPoints - szQuery: %s", szQuery);
	}
	g_dDb.Query(db_viewPlayerPointsCallback, szQuery, GetClientUserId(client), DBPrio_Low);
}

public void db_viewPlayerPointsCallback(Database db, DBResultSet results, const char[] error, any userid)
{
	int client = GetClientOfUserId(userid);

	if (IsValidClient(client))
	{
		if (!IsValidDatabase(db, error))
		{
			LogError("[SurfTimer] SQL Error (db_viewPlayerPointsCallback): %s", error);
			if (!g_bSettingsLoaded[client])
				LoadClientSetting(client, g_iSettingToLoad[client]);
			return;
		}
		// SELECT steamid, name, points, finishedmapspro, country, lastseen, timealive, timespec, connections from ck_playerrank where steamid='%s';
		// Old player - get points
		if (results.HasResults)
		{
			int style;
			
			while (results.FetchRow())
			{
				style = results.FetchInt(10);
				g_pr_points[client][style] = results.FetchInt(2);
				g_pr_finishedmaps[client][style] = results.FetchInt(3);
				g_pr_finishedmaps_perc[client][style] = (float(g_pr_finishedmaps[client][style]) / float(g_pr_MapCount[0])) * 100.0;
				if (style == 0)
				{
					g_iPlayTimeAlive[client] = results.FetchInt(6);
					g_iPlayTimeSpec[client] = results.FetchInt(7);
					g_iTotalConnections[client] = results.FetchInt(8);
				}
			}
			
			g_iTotalConnections[client]++;

			char updateConnections[1024];
			Format(updateConnections, 1024, "UPDATE ck_playerrank SET connections = connections + 1 WHERE steamid = '%s';", g_szSteamID[client]);
			if (g_cLogQueries.BoolValue)
			{
				LogToFile(g_szQueryFile, "db_viewPlayerPointsCallback - szQuery: %s", updateConnections);
			}
			g_dDb.Query(SQL_CheckCallback, updateConnections, _, DBPrio_Low);

			// Debug
			g_fTick[client][1] = GetGameTime();
			float tick = g_fTick[client][1] - g_fTick[client][0];
			LogToFileEx(g_szLogFile, "[SurfTimer] %s: Finished db_viewPlayerPoints in %fs", g_szSteamID[client], tick);
			g_fTick[client][0] = GetGameTime();
			
			// Count players rank
			if (IsValidClient(client))
				for (int i = 0; i < MAX_STYLES; i++)
					db_GetPlayerRank(client, i);
		}
		else
		{
			if (IsValidClient(client))
			{
				// New player - insert
				char szQuery[512];
				char szUName[MAX_NAME_LENGTH];

				if (IsValidClient(client))
					GetClientName(client, szUName, MAX_NAME_LENGTH);
				else
					return;

				// SQL injection protection
				char szName[MAX_NAME_LENGTH * 2 + 1];
				g_dDb.Escape(szUName, szName, MAX_NAME_LENGTH * 2 + 1);

				char szSteamId64[64];
				GetClientAuthId(client, AuthId_SteamID64, szSteamId64, MAX_NAME_LENGTH, true);

				Format(szQuery, sizeof(szQuery), sql_insertPlayerRank, g_szSteamID[client], szSteamId64, szName, g_szCountry[client], GetTime());
				if (g_cLogQueries.BoolValue)
				{
					LogToFile(g_szQueryFile, "db_viewPlayerPointsCallback - szQuery: %s", szQuery);
				}
				g_dDb.Query(SQL_CheckCallback, szQuery, _, DBPrio_Low);

				// Play time
				g_iPlayTimeAlive[client] = 0;
				g_iPlayTimeSpec[client] = 0;

				// Debug
				g_fTick[client][1] = GetGameTime();
				float tick = g_fTick[client][1] - g_fTick[client][0];
				LogToFileEx(g_szLogFile, "[SurfTimer] %s: Finished db_viewPlayerPoints in %fs", g_szSteamID[client], tick);
				g_fTick[client][0] = GetGameTime();

				// Count players rank
				for (int i = 0; i < MAX_STYLES; i++)
					db_GetPlayerRank(client, i);
			}
		}
	}
}

// Get the amount of players, who have more points
public void db_GetPlayerRank(int client, int style)
{
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, style);

	if (IsValidClient(client))
	{
		char szQuery[512];
		// "SELECT COUNT(*) FROM ck_playerrank WHERE points >= (SELECT points FROM ck_playerrank WHERE steamid = '%s') ORDER BY points";
		Format(szQuery, sizeof(szQuery), sql_selectRankedPlayersRank, style, g_szSteamID[client], style);
		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "db_GetPlayerRank - szQuery: %s", szQuery);
		}
		g_dDb.Query(sql_selectRankedPlayersRankCallback, szQuery, pack, DBPrio_Low);
	}
}

public void sql_selectRankedPlayersRankCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int style = ReadPackCell(pack);
	delete pack;

	if (IsValidClient(client))
	{
		if (!IsValidDatabase(db, error))
		{
			LogError("[SurfTimer] SQL Error (sql_selectRankedPlayersRankCallback): %s", error);
			if (!g_bSettingsLoaded[client])
				LoadClientSetting(client, g_iSettingToLoad[client]);
			return;
		}

		if (results.HasResults && results.FetchRow())
		{
			g_PlayerRank[client][style] = results.FetchInt(0);
			if (GetConVarInt(g_hPrestigeRank) > 0)
			{
				if (GetConVarBool(g_hPrestigeStyles) && !g_bPrestigeAvoid[client])
				{
					if (style == 0)
					{
						if (g_PlayerRank[client][0] > GetConVarInt(g_hPrestigeRank) && !g_bPrestigeCheck[client])
							KickClient(client, "You must be at least rank %i to join this server", GetConVarInt(g_hPrestigeRank));
					}

					if (style == MAX_STYLES && !g_bPrestigeCheck[client])
						KickClient(client, "You must be at least rank %i to join this server", GetConVarInt(g_hPrestigeRank));
				}
				else
				{
					if (g_PlayerRank[client][0] < GetConVarInt(g_hPrestigeRank) || g_bPrestigeCheck[client])
						g_bPrestigeCheck[client] = true;
					else if (!g_bPrestigeAvoid[client])
						KickClient(client, "You must be at least rank %i to join this server", GetConVarInt(g_hPrestigeRank));
				}
			}

			// Custom Title Access
			if (g_PlayerRank[client][0] <= 3 && g_PlayerRank[client][0] > 0) // Rank 1-3
				g_bCustomTitleAccess[client] = true;

			// Sort players by rank in scoreboard
			if (style == 0)
			{
				if (g_pr_AllPlayers[style] < g_PlayerRank[client][style] || g_PlayerRank[client][style] == 0)
					CS_SetClientContributionScore(client, -99999);
				else
					CS_SetClientContributionScore(client, -g_PlayerRank[client][style]);
			}
		}
		else if (style == 0 && GetConVarInt(g_hPrestigeRank) > 0 && !g_bPrestigeCheck[client])
			KickClient(client, "You must be at least rank %i to join this server", GetConVarInt(g_hPrestigeRank));

		if (!g_bSettingsLoaded[client] && style == (MAX_STYLES - 1))
		{
			g_fTick[client][1] = GetGameTime();
			float tick = g_fTick[client][1] - g_fTick[client][0];
			LogToFileEx(g_szLogFile, "[SurfTimer] %s: Finished db_GetPlayerRank in %fs", g_szSteamID[client], tick);
			g_fTick[client][0] = GetGameTime();

			LoadClientSetting(client, g_iSettingToLoad[client]);
		}
	}
}

public void db_viewPlayerProfile(int client, int style, char szSteamId[32], bool bPlayerFound, char szName[MAX_NAME_LENGTH])
{
	char szQuery[512];
	Format(g_pr_szrank[client], 512, "");

	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, style);
	WritePackString(pack, szSteamId);
	WritePackString(pack, szName);

	if (bPlayerFound)
	{
		// "SELECT COUNT(*) FROM ck_playerrank WHERE style = %i AND points >= (SELECT points FROM ck_playerrank WHERE steamid = '%s' AND style = %i);";
		Format(szQuery, sizeof(szQuery), sql_selectRankedPlayersRank, style, szSteamId, style);
		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "db_viewPlayerProfile - szQuery: %s", szQuery);
		}
		g_dDb.Query(sql_selectPlayerRankCallback, szQuery, pack, DBPrio_Low);
	}
	else
	{
		// "SELECT steamid, steamid64, name, country, points, wrpoints, wrbpoints, top10points, groupspoints, mappoints, bonuspoints, finishedmapspro, finishedbonuses, finishedstages, wrs, wrbs, wrcps, top10s, groups, lastseen FROM ck_playerrank WHERE name LIKE '%c%s%c' AND style = '%i';"; sql_selectUnknownProfile
		Format(szQuery, sizeof(szQuery), "SELECT steamid FROM ck_playerrank WHERE style = %i AND name LIKE '%c%s%c' LIMIT 1;", style, PERCENT, szName, PERCENT);
		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "db_viewPlayerProfile - szQuery: %s", szQuery);
		}
		g_dDb.Query(sql_selectUnknownPlayerCallback, szQuery, pack, DBPrio_Low);
	}
}

public void sql_selectUnknownPlayerCallback (Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_selectUnknownPlayerCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int style = ReadPackCell(pack);
	char szSteamId[32], szName[MAX_NAME_LENGTH];
	ReadPackString(pack, szSteamId, sizeof(szSteamId));
	ReadPackString(pack, szName, sizeof(szName));

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			results.FetchString(0, szSteamId, sizeof(szSteamId));

			// Remake pack
			ResetPack(pack, true);
			WritePackCell(pack, GetClientUserId(client));
			WritePackCell(pack, style);
			WritePackString(pack, szSteamId);
			WritePackString(pack, szName);

			// "SELECT COUNT(*) FROM ck_playerrank WHERE style = %i AND points >= (SELECT points FROM ck_playerrank WHERE steamid = '%s' AND style = %i) ORDER BY points";
			char szQuery[512];
			Format(szQuery, sizeof(szQuery), sql_selectRankedPlayersRank, style, szSteamId, style);
			if (g_cLogQueries.BoolValue)
			{
				LogToFile(g_szQueryFile, "sql_selectUnknownPlayerCallback - szQuery: %s", szQuery);
			}
			g_dDb.Query(sql_selectPlayerRankCallback, szQuery, pack, DBPrio_Low);
		}
		else
		{
			CPrintToChat(client, "%t", "SQL40", g_szChatPrefix, szName);
			delete pack;
		}
	}
}

public void sql_selectPlayerRankCallback (Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_selectPlayerRankCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int style = ReadPackCell(pack);
	char szSteamId[32], szName[MAX_NAME_LENGTH];
	ReadPackString(pack, szSteamId, sizeof(szSteamId));
	ReadPackString(pack, szName, sizeof(szName));

	if (results.HasResults && results.FetchRow())
	{
		WritePackCell(pack, results.FetchInt(0));
 
		// "SELECT steamid, steamid64, name, country, points, wrpoints, wrbpoints, wrcppoints, top10points, groupspoints, mappoints, bonuspoints, finishedmapspro, finishedbonuses, finishedstages, wrs, wrbs, wrcps, top10s, groups, lastseen FROM ck_playerrank WHERE steamid = '%s' AND style = '%i';";
		char szQuery[512];
		Format(szQuery, sizeof(szQuery), sql_selectPlayerProfile, szSteamId, style);
		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "sql_selectPlayerRankCallback - szQuery: %s", szQuery);
		}
		g_dDb.Query(sql_selectPlayerProfileCallback, szQuery, pack, DBPrio_Low);
	}
	else
	{
		if (IsValidClient(client))
		{
			CPrintToChat(client, "%t", "SQL40", g_szChatPrefix, szName);
		}

		delete pack;
	}
}

public void sql_selectPlayerProfileCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_selectPlayerProfileCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int style = ReadPackCell(pack);
	char szSteamId[32], szName2[MAX_NAME_LENGTH];
	ReadPackString(pack, szSteamId, sizeof(szSteamId));
	ReadPackString(pack, szName2, sizeof(szName2));
	int rank = ReadPackCell(pack);
	delete pack;

	// "SELECT steamid, steamid64, name, country, points, wrpoints, wrbpoints, wrcppoints top10points, groupspoints, mappoints, bonuspoints, finishedmapspro, finishedbonuses, finishedstages, wrs, wrbs, wrcps, top10s, groups, lastseen FROM ck_playerrank WHERE steamid = '%s' AND style = '%i';";

	if (results.HasResults && results.FetchRow())
	{
		char szName[MAX_NAME_LENGTH], szSteamId2[32], szCountry[64];

		results.FetchString(0, szSteamId2, sizeof(szSteamId2));
		Format(g_szProfileSteamId[client], sizeof(g_szProfileSteamId[]), szSteamId2);
		results.FetchString(2, szName, sizeof(szName));
		Format(g_szProfileName[client], sizeof(g_szProfileName), szName);
		results.FetchString(3, szCountry, sizeof(szCountry));
		int points = results.FetchInt(4);
		int wrPoints = results.FetchInt(5);
		int wrbPoints = results.FetchInt(6);
		int wrcpPoints = results.FetchInt(7);
		int top10Points = results.FetchInt(8);
		int groupPoints = results.FetchInt(9);
		int mapPoints = results.FetchInt(10);
		int bonusPoints = results.FetchInt(11);
		int finishedMaps = results.FetchInt(12);
		int finishedBonuses = results.FetchInt(13);
		int finishedStages = results.FetchInt(14);
		int wrs = results.FetchInt(15);
		int wrbs = results.FetchInt(16);
		int wrcps = results.FetchInt(17);
		int top10s = results.FetchInt(18);
		int groups = results.FetchInt(19);
		int lastseen = results.FetchInt(20);

		if (finishedMaps > g_pr_MapCount[0])
			finishedMaps = g_pr_MapCount[0];
		
		if (finishedBonuses > g_pr_BonusCount)
			finishedBonuses = g_pr_BonusCount;
		
		if (finishedStages > g_pr_StageCount)
			finishedStages = g_pr_StageCount;

		int totalCompleted = finishedMaps + finishedBonuses + finishedStages;
		int totalZones = g_pr_MapCount[0] + g_pr_BonusCount + g_pr_StageCount;

		// Completion Percentage 
		float fPerc, fBPerc, fSPerc, fTotalPerc;
		char szPerc[32], szBPerc[32], szSPerc[32], szTotalPerc[32];

		// Calculate percentages and format them into strings
		fPerc = (float(finishedMaps) / (float(g_pr_MapCount[0]))) * 100.0;
		fBPerc = (float(finishedBonuses) / (float(g_pr_BonusCount))) * 100.0;
		fSPerc = (float(finishedStages) / (float(g_pr_StageCount))) * 100.0;
		fTotalPerc = (float(totalCompleted) / (float(totalZones))) * 100.0;

		FormatPercentage(fPerc, szPerc, sizeof(szPerc));
		FormatPercentage(fBPerc, szBPerc, sizeof(szBPerc));
		FormatPercentage(fSPerc, szSPerc, sizeof(szSPerc));
		FormatPercentage(fTotalPerc, szTotalPerc, sizeof(szTotalPerc));

		// Get players skillgroup
		SkillGroup RankValue;
		int index = GetSkillgroupIndex(rank, points);
		GetArrayArray(g_hSkillGroups, index, RankValue, sizeof(SkillGroup));
		char szSkillGroup[128];
		Format(szSkillGroup, sizeof(szSkillGroup), RankValue.RankName);
		CRemoveTags(szSkillGroup, sizeof(szSkillGroup));
		ReplaceString(szSkillGroup, sizeof(szSkillGroup), "{style}", "");

		char szRank[32];
		if (rank > g_pr_RankedPlayers[0] || points == 0)
			Format(szRank, 32, "-");
		else
			Format(szRank, 32, "%i", rank);

		// Format Profile Menu
		char szCompleted[1024], szMapPoints[128], szBonusPoints[128], szTop10Points[128], szStagePc[128], szMiPc[128], szRecords[128], szLastSeen[128];
		
		// Get last seen
		int time = GetTime();
		int unix = time - lastseen;
		diffForHumans(unix, szLastSeen, sizeof(szLastSeen), 1);

		Format(szMapPoints, 128, "Maps: %i/%i - [%i] (%s%c)", finishedMaps, g_pr_MapCount[0], mapPoints, szPerc, PERCENT);

		if (wrbPoints > 0)
			Format(szBonusPoints, 128, "Bonuses: %i/%i - [%i+%i] (%s%c)", finishedBonuses, g_pr_BonusCount, bonusPoints, wrbPoints, szBPerc, PERCENT);
		else
			Format(szBonusPoints, 128, "Bonuses: %i/%i - [%i] (%s%c)", finishedBonuses, g_pr_BonusCount, bonusPoints, szBPerc, PERCENT);

		if (wrPoints > 0)
			Format(szTop10Points, 128, "Top10: %i - [%i+%i]", top10s, top10Points, wrPoints);
		else
			Format(szTop10Points, 128, "Top10: %i - [%i]", top10s, top10Points);

		if (wrcpPoints > 0)
			Format(szStagePc, 128, "Stages: %i/%i [0+%d] (%s%c)", finishedStages, g_pr_StageCount, wrcpPoints, szSPerc, PERCENT);
		else
			Format(szStagePc, 128, "Stages: %i/%i [0] (%s%c)", finishedStages, g_pr_StageCount, szSPerc, PERCENT);

		Format(szMiPc, 128, "Map Improvement Pts: %i - [%i]", groups, groupPoints);

		Format(szRecords, 128, "Records:\nMap WR: %i\nStage WR: %i\nBonus WR: %i", wrs, wrcps, wrbs);

		Format(szCompleted, 1024, "Completed - Points (%s%c):\n%s\n%s\n%s\n%s\n \n%s\n \n%s\n \n", szTotalPerc, PERCENT, szMapPoints, szBonusPoints, szTop10Points, szStagePc, szMiPc, szRecords);

		Format(g_pr_szrank[client], 512, "Rank: %s/%i %s\nTotal pts: %i\n \n", szRank, g_pr_RankedPlayers[style], szSkillGroup, points);
		
		char szTop[128];
		if (style > 0)
			Format(szTop, sizeof(szTop), "[%s | %s | Online: %s]\n", szName, g_szStyleMenuPrint[style], szLastSeen);
		else
			Format(szTop, sizeof(szTop), "[%s ||| Online: %s]\n", szName, szLastSeen);

		char szTitle[1024];
		if (GetConVarBool(g_hCountry))
			Format(szTitle, 1024, "%s-------------------------------------\n%s\nCountry: %s\n \n%s\n", szTop, szSteamId, szCountry, g_pr_szrank[client]);
		else
			Format(szTitle, 1024, "%s-------------------------------------\n%s\n \n%s", szTop, szSteamId, g_pr_szrank[client]);

		Menu menu = CreateMenu(ProfileMenuHandler);
		SetMenuTitle(menu, szTitle);
		AddMenuItem(menu, "Finished maps", szCompleted);
		AddMenuItem(menu, szSteamId, "Player Info");

		if (IsValidClient(client))
			if (StrEqual(szSteamId, g_szSteamID[client]))
				AddMenuItem(menu, "Refresh my profile", "Refresh my profile");

		SetMenuExitButton(menu, true);
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
	}
}

public int ProfileMenuHandler(Handle menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		switch (item)
		{
			case 0: completionMenu(client);
			case 1:
			{
				char szSteamId[32];
				GetMenuItem(menu, item, szSteamId, 32);
				db_viewPlayerInfo(client, szSteamId);
			}
			case 2:
			{
				if (g_bRecalcRankInProgess[client])
				{
					CPrintToChat(client, "%t", "SQL1", g_szChatPrefix);
				}
				else
				{
					g_bRecalcRankInProgess[client] = true;
					CPrintToChat(client, "%t", "Rc_PlayerRankStart", g_szChatPrefix);
					CalculatePlayerRank(client, g_ProfileStyleSelect[client]);
				}
			}
		}
	}
	else if (action == MenuAction_Cancel)
	{
		if (1 <= client <= MaxClients && IsValidClient(client))
		{
			switch (g_MenuLevel[client])
			{
				case 0:db_selectTopPlayers(client, 0);
				case 3:db_viewWrcpMap(client, g_szWrcpMapSelect[client]);
			}
			if (g_MenuLevel[client] < 0)
			{
				if (g_bSelectProfile[client])
					ProfileMenu2(client, g_ProfileStyleSelect[client], "", "");
			}
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public void completionMenu(int client)
{
	int style = g_ProfileStyleSelect[client];
	char szTitle[128];
	if (style == 0)
		Format(szTitle, 128, "[%s | Completion Menu]\n \n", g_szProfileName[client]);
	else
		Format(szTitle, 128, "[%s | %s | Completion Menu]\n \n", g_szProfileName[client], g_szStyleMenuPrint[style]);

	Menu theCompletionMenu = CreateMenu(CompletionMenuHandler);
	SetMenuTitle(theCompletionMenu, szTitle);
	AddMenuItem(theCompletionMenu, "Complete Maps", "Complete Maps");
	AddMenuItem(theCompletionMenu, "Incomplete Maps", "Incomplete Maps");
	AddMenuItem(theCompletionMenu, "Top 10 Maps", "Top 10 Maps");
	AddMenuItem(theCompletionMenu, "WRs", "WRs");
	SetMenuExitBackButton(theCompletionMenu, true);
	DisplayMenu(theCompletionMenu, client, MENU_TIME_FOREVER);
}

public int CompletionMenuHandler(Handle menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		switch (item)
		{
			case 0:db_viewAllRecords(client, g_szProfileSteamId[client]);
			case 1:db_viewUnfinishedMaps(client, g_szProfileSteamId[client]);
			case 2:db_viewTop10Records(client, g_szProfileSteamId[client], 0);
			case 3:db_viewTop10Records(client, g_szProfileSteamId[client], 1);
		}
	}
	else if (action == MenuAction_Cancel)
		db_viewPlayerProfile(client, g_ProfileStyleSelect[client], g_szProfileSteamId[client], true, "");
	else if (action == MenuAction_End)
		delete menu;
}

public void ContinueRecalc(int client)
{
	// ON RECALC ALL
	if (client > MAXPLAYERS)
		CalculatePlayerRank(client, 0);
	else
	{
		// ON CONNECT
		if (!IsValidClient(client) || IsFakeClient(client))
			return;
		
		float diff = GetGameTime() - g_fMapStartTime + 1.5;
		if (GetClientTime(client) < diff)
		{
			CalculatePlayerRank(client, 0);
		}
		else
		{
			db_viewPlayerPoints(client);
		}
	}
}

/*==================================
=           PLAYER TIMES           =
==================================*/

public void db_GetMapRecord_Pro()
{
	g_fRecordMapTime = 9999999.0;
	for (int i = 1; i < MAX_STYLES; i++)
		g_fRecordStyleMapTime[i] = 9999999.0;
	
	for (int i = 0; i < 3; i++)
	{
		g_iStartVelsServerRecord[0][i] = 0;
		g_iEndVelsServerRecord[0][i] = 0;
	}

	char szQuery[512];
	// SELECT MIN(runtimepro), name, steamid, style FROM ck_playertimes WHERE mapname = '%s' AND runtimepro > -1.0 GROUP BY style
	Format(szQuery, sizeof(szQuery), sql_selectMapRecord, g_szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_GetMapRecord_Pro - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_selectMapRecordCallback, szQuery, _, DBPrio_Low);
}

public void sql_selectMapRecordCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		if (StrContains(error, "Unknown column", false) != -1)
		{
			LogError("[Surftimer] (sql_selectMapRecordCallback) Your database are not up to date! Please use the command \"sm_surftimer_upgrade\" to upgrade your database.");
		}
		else
		{
			LogError("[Surftimer] SQL Error (sql_selectMapRecordCallback): %s", error);
		}

		if (!g_bServerDataLoaded)
		{
			db_viewMapProRankCount();
			CreateTimer(3.0, RefreshZonesTimer, _, TIMER_FLAG_NO_MAPCHANGE);
		}
		return;
	}

	int style;

	if (results.HasResults)
	{
		while (results.FetchRow())
		{
			style = results.FetchInt(9);
			if (style == 0)
			{
				g_fRecordMapTime = results.FetchFloat(0);

				if (g_fRecordMapTime > -1.0 && !results.IsFieldNull(0))
				{
					g_fRecordMapTime = results.FetchFloat(0);

					g_iStartVelsServerRecord[0][0] = results.FetchInt(3);
					g_iStartVelsServerRecord[0][1] = results.FetchInt(4);
					g_iStartVelsServerRecord[0][2] = results.FetchInt(5);
					g_iEndVelsServerRecord[0][0] = results.FetchInt(6);
					g_iEndVelsServerRecord[0][1] = results.FetchInt(7);
					g_iEndVelsServerRecord[0][2] = results.FetchInt(8);

					FormatTimeFloat(0, g_fRecordMapTime, 3, g_szRecordMapTime, 64);
					results.FetchString(1, g_szRecordPlayer, MAX_NAME_LENGTH);
					results.FetchString(2, g_szRecordMapSteamID, MAX_NAME_LENGTH);
				}
				else
				{
					Format(g_szRecordMapTime, 64, "N/A");
					g_fRecordMapTime = 9999999.0;
				}
			}
			else
			{
				g_fRecordStyleMapTime[style] = results.FetchFloat(0);

				if (g_fRecordStyleMapTime[style] > -1.0 && !results.IsFieldNull(0))
				{
					g_fRecordStyleMapTime[style] = results.FetchFloat(0);
					FormatTimeFloat(0, g_fRecordStyleMapTime[style], 3, g_szRecordStyleMapTime[style], 64);
					results.FetchString(1, g_szRecordStylePlayer[style], MAX_NAME_LENGTH);
					results.FetchString(2, g_szRecordStyleMapSteamID[style], MAX_NAME_LENGTH);
				}
				else
				{
					Format(g_szRecordStyleMapTime[style], 64, "N/A");
					g_fRecordStyleMapTime[style] = 9999999.0;
				}
			}
		}
	}
	else
	{
		Format(g_szRecordMapTime, 64, "N/A");
		g_fRecordMapTime = 9999999.0;
		for (int i = 1; i < MAX_STYLES; i++)
		{
			Format(g_szRecordStyleMapTime[i], 64, "N/A");
			g_fRecordStyleMapTime[i] = 9999999.0;
		}
	}
	if (!g_bServerDataLoaded)
	{
		db_viewMapProRankCount();
		CreateTimer(3.0, RefreshZonesTimer, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	return;
}

public void db_selectTopSurfers(int client, char mapname[128])
{
	char szQuery[1024];
	Format(szQuery, sizeof(szQuery), sql_selectTopSurfers, mapname);
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackString(pack, mapname);
	WritePackCell(pack, 0);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectTopSurfers - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_selectTopSurfersCallback, szQuery, pack, DBPrio_Low);
}

public void db_selectMapTopSurfers(int client, char mapname[128])
{
	char szQuery[1024];
	char type[128];
	type = "normal";
	Format(szQuery, sizeof(szQuery), sql_selectTopSurfers, mapname);
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackString(pack, mapname);
	WritePackString(pack, type);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectMapTopSurfers - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_selectTopSurfersCallback, szQuery, pack, DBPrio_Low);
}

public void sql_selectTopSurfersCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_selectTopSurfersCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	char szMap[128];
	ReadPackString(pack, szMap, 128);
	int style = 0; // ReadPackCell(pack);
	delete pack;

	if (IsValidClient(client))
	{
		char szFirstMap[128];
		char szValue[128];
		char szName[64];
		float time;
		char szSteamID[32];
		char lineBuf[256];
		Handle stringArray = CreateArray(100);

		Handle menu;
		menu = CreateMenu(MapMenuHandler1);
		SetMenuPagination(menu, 5);

		bool bduplicat = false;
		char title[256];
		if (results.HasResults)
		{
			int i = 1;
			while (results.FetchRow())
			{
				bduplicat = false;
				results.FetchString(0, szSteamID, 32);
				results.FetchString(1, szName, 64);
				time = results.FetchFloat(2);
				results.FetchString(4, szMap, 128);

				if (i == 1 || (i > 1 && StrEqual(szFirstMap, szMap)))
				{
					int stringArraySize = GetArraySize(stringArray);
					for (int x = 0; x < stringArraySize; x++)
					{
						GetArrayString(stringArray, x, lineBuf, sizeof(lineBuf));
						if (StrEqual(lineBuf, szName, false))
							bduplicat = true;
					}
					if (bduplicat == false && i < 51)
					{
						char szTime[32];
						FormatTimeFloat(client, time, 3, szTime, sizeof(szTime));

						if (time < 3600.0)
							Format(szTime, 32, "   %s", szTime);
						if (i == 100)
							Format(szValue, 128, "[%i.] %s |    » %s", i, szTime, szName);
						if (i >= 10)
							Format(szValue, 128, "[%i.] %s |    » %s", i, szTime, szName);
						else
							Format(szValue, 128, "[0%i.] %s |    » %s", i, szTime, szName);

						AddMenuItem(menu, szSteamID, szValue, ITEMDRAW_DEFAULT);
						PushArrayString(stringArray, szName);

						if (i == 1)
							Format(szFirstMap, 128, "%s", szMap);
						i++;
					}
				}
			}
			if (i == 1)
			{
				CPrintToChat(client, "%t", "NoTopRecords", g_szChatPrefix, szMap);
			}
		}
		else
			CPrintToChat(client, "%t", "NoTopRecords", g_szChatPrefix, szMap);

		switch (style)
		{
			case 1: Format(title, 256, "Top 50 SW Times on %s \n    Rank    Time               Player", szFirstMap);
			case 2: Format(title, 256, "Top 50 HSW Times on %s \n    Rank    Time               Player", szFirstMap);
			case 3: Format(title, 256, "Top 50 BW Times on %s \n    Rank    Time               Player", szFirstMap);
			case 4: Format(title, 256, "Top 50 Low-Gravity Times on %s \n    Rank    Time               Player", szFirstMap);
			case 5: Format(title, 256, "Top 50 Slow Motion Times on %s \n    Rank    Time               Player", szFirstMap);
			case 6: Format(title, 256, "Top 50 Fast Forward Times on %s \n    Rank    Time               Player", szFirstMap);
			case 7: Format(title, 256, "Top 50 Freestyle Times on %s \n    Rank    Time               Player", szFirstMap);
			default: Format(title, 256, "Top 50 Times on %s \n    Rank    Time               Player", szFirstMap);
		}

		delete stringArray;
		SetMenuTitle(menu, title);
		SetMenuOptionFlags(menu, MENUFLAG_BUTTON_EXIT);
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
	}
}


// BONUS
public void db_selectBonusesInMap(int client, char mapname[128])
{
	// SELECT mapname, zonegroup, zonename FROM `ck_zones` WHERE mapname LIKE '%c%s%c' AND zonegroup > 0 GROUP BY zonegroup;
	char szQuery[512];
	Format(szQuery, sizeof(szQuery), sql_selectBonusesInMap, PERCENT, mapname, PERCENT);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectBonusesInMap - szQuery: %s", szQuery);
	}
	g_dDb.Query(db_selectBonusesInMapCallback, szQuery, GetClientUserId(client), DBPrio_Low);
}

public void db_selectBonusesInMapCallback(Database db, DBResultSet results, const char[] error, any userid)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_selectBonusesInMapCallback): %s", error);
		return;
	}

	int client = GetClientOfUserId(userid);

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			char mapname[128], MenuTitle[248], BonusName[128], MenuID[248];
			int zGrp;

			if (results.RowCount == 1)
			{
				results.FetchString(0, mapname, 128);
				db_selectBonusTopSurfers(client, mapname, results.FetchInt(1));
				return;
			}

			Menu listBonusesinMapMenu = new Menu(MenuHandler_SelectBonusinMap);

			results.FetchString(0, mapname, 128);
			zGrp = results.FetchInt(1);
			Format(MenuTitle, 248, "Choose a Bonus in %s", mapname);
			listBonusesinMapMenu.SetTitle(MenuTitle);

			results.FetchString(2, BonusName, 128);

			if (!BonusName[0])
				Format(BonusName, 128, "bonus %i", zGrp);

			Format(MenuID, 248, "%s-%i", mapname, zGrp);

			listBonusesinMapMenu.AddItem(MenuID, BonusName);


			while (results.FetchRow())
			{
				results.FetchString(2, BonusName, 128);
				zGrp = results.FetchInt(1);

				if (StrEqual(BonusName, "NULL", false))
					Format(BonusName, 128, "bonus %i", zGrp);

				Format(MenuID, 248, "%s-%i", mapname, zGrp);

				listBonusesinMapMenu.AddItem(MenuID, BonusName);
			}

			listBonusesinMapMenu.ExitButton = true;
			listBonusesinMapMenu.Display(client, 60);
		}
		else
		{
			CPrintToChat(client, "%t", "SQL2", g_szChatPrefix);
			return;
		}
	}
}

public int MenuHandler_SelectBonusinMap(Handle sMenu, MenuAction action, int client, int item)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char aID[248];
			char splits[2][128];
			GetMenuItem(sMenu, item, aID, sizeof(aID));
			ExplodeString(aID, "-", splits, sizeof(splits), sizeof(splits[]));

			db_selectBonusTopSurfers(client, splits[0], StringToInt(splits[1]));
		}
		case MenuAction_End:
		{
			delete sMenu;
		}
	}
}

public void db_selectBonusTopSurfers(int client, char mapname[128], int zGrp)
{
	char szQuery[1024];
	Format(szQuery, sizeof(szQuery), sql_selectTopBonusSurfers, mapname, zGrp);
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackString(pack, mapname);
	WritePackCell(pack, zGrp);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectBonusTopSurfers - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_selectTopBonusSurfersCallback, szQuery, pack, DBPrio_Low);
}

public void sql_selectTopBonusSurfersCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_selectTopBonusSurfersCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	char szMap[128];
	ReadPackString(pack, szMap, 128);
	int zGrp = ReadPackCell(pack);
	delete pack;

	if (IsValidClient(client))
	{
		char szFirstMap[128], szValue[128], szName[64], szSteamID[32], lineBuf[256], title[256];
		float time;
		bool bduplicat = false;
		Handle stringArray = CreateArray(100);
		Menu topMenu;

		topMenu = new Menu(MapMenuHandler1);

		topMenu.Pagination = 5;

		if (results.HasResults)
		{
			int i = 1;
			while (results.FetchRow())
			{
				bduplicat = false;
				results.FetchString(0, szSteamID, 32);
				results.FetchString(1, szName, 64);
				time = results.FetchFloat(2);
				results.FetchString(4, szMap, 128);
				if (i == 1 || (i > 1 && StrEqual(szFirstMap, szMap)))
				{
					int stringArraySize = GetArraySize(stringArray);
					for (int x = 0; x < stringArraySize; x++)
					{
						GetArrayString(stringArray, x, lineBuf, sizeof(lineBuf));
						if (StrEqual(lineBuf, szName, false))
						bduplicat = true;
					}
					if (bduplicat == false && i < 51)
					{
						char szTime[32];
						FormatTimeFloat(client, time, 3, szTime, sizeof(szTime));
						if (time < 3600.0)
						Format(szTime, 32, "   %s", szTime);
						if (i == 100)
						Format(szValue, 128, "[%i.] %s |    » %s", i, szTime, szName);
						if (i >= 10)
						Format(szValue, 128, "[%i.] %s |    » %s", i, szTime, szName);
						else
						Format(szValue, 128, "[0%i.] %s |    » %s", i, szTime, szName);
						topMenu.AddItem(szSteamID, szValue, ITEMDRAW_DEFAULT);
						PushArrayString(stringArray, szName);
						if (i == 1)
						Format(szFirstMap, 128, "%s", szMap);
						i++;
					}
				}
			}
			if (i == 1)
			{
				CPrintToChat(client, "%t", "NoTopRecords", g_szChatPrefix, szMap);
			}
		}
		else
		{
			CPrintToChat(client, "%t", "NoTopRecords", g_szChatPrefix, szMap);
			Format(title, 256, "Top 50 Times on %s (B %i) \n    Rank    Time               Player", szFirstMap, zGrp);
			topMenu.SetTitle(title);
			topMenu.OptionFlags = MENUFLAG_BUTTON_EXIT;
			topMenu.Display(client, MENU_TIME_FOREVER);
			delete stringArray;
		}
	}
}

public void db_currentRunRank(int client)
{
	if (!IsValidClient(client))
	{
		return;
	}

	char szQuery[512];
	Format(szQuery, sizeof(szQuery), "SELECT count(runtimepro)+1 FROM `ck_playertimes` WHERE `mapname` = '%s' AND `runtimepro` < %f;", g_szMapName, g_fFinalTime[client]);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_currentRunRank - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_CurrentRunRankCallback, szQuery, GetClientUserId(client), DBPrio_Low);
}

public void SQL_CurrentRunRankCallback(Database db, DBResultSet results, const char[] error, any userid)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_CurrentRunRankCallback): %s", error);
		return;
	}
	// Get players rank, 9999999 = error
	int rank;
	if (results.HasResults && results.FetchRow())
	{
		rank = results.FetchInt(0);
	}

	int client = GetClientOfUserId(userid);

	if (IsValidClient(client))
	{
		MapFinishedMsgs(client, rank);
	}
}

// Get clients record from database
// Called when a player finishes a map
public void db_selectRecord(int client)
{
	if (!IsValidClient(client))
	return;

	char szQuery[255];
	Format(szQuery, sizeof(szQuery), "SELECT runtimepro FROM ck_playertimes WHERE steamid = '%s' AND mapname = '%s' AND runtimepro > -1.0 AND style = 0;", g_szSteamID[client], g_szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectRecord - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_selectRecordCallback, szQuery, GetClientUserId(client), DBPrio_Low);
}

public void sql_selectRecordCallback(Database db, DBResultSet results, const char[] error, int userid)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[Surftimer] SQL Error (sql_selectRecordCallback): %s", error);
		return;
	}

	int client = GetClientOfUserId(userid);

	if (!IsValidClient(client))
	{
		return;
	}


	char szQuery[512];

	// Found old time from database
	if (results.HasResults && results.FetchRow())
	{
		float time = results.FetchFloat(0);

		// If old time was slower than the new time, update record
		if ((g_fFinalTime[client] <= time || time <= 0.0))
		{
			db_updateRecordPro(client);
		}
	}
	else
	{ // No record found from database - Let's insert

		// Escape name for SQL injection protection
		char szName[MAX_NAME_LENGTH * 2 + 1], szUName[MAX_NAME_LENGTH];
		GetClientName(client, szUName, MAX_NAME_LENGTH);
		g_dDb.Escape(szUName, szName, MAX_NAME_LENGTH);

		// Move required information in datapack
		Handle pack = CreateDataPack();
		WritePackFloat(pack, g_fFinalTime[client]);
		WritePackCell(pack, GetClientUserId(client));

		Format(szQuery, sizeof(szQuery), sql_insertPlayerTime, g_szSteamID[client], g_szMapName, szName, g_fFinalTime[client], g_iStartVelsNew[client][0][0], g_iStartVelsNew[client][0][1], g_iStartVelsNew[client][0][2], g_iEndVelsNew[client][0][0], g_iEndVelsNew[client][0][1], g_iEndVelsNew[client][0][2], 0);
		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "sql_selectRecordCallback - szQuery: %s", szQuery);
		}
		g_dDb.Query(SQL_UpdateRecordProCallback, szQuery, pack, DBPrio_Low);

		g_bInsertNewTime = true;
	}
}

// If latest record was faster than old - Update time
public void db_updateRecordPro(int client)
{
	char szUName[MAX_NAME_LENGTH];

	if (IsValidClient(client))
		GetClientName(client, szUName, MAX_NAME_LENGTH);
	else
		return;

	// Also updating name in database, escape string
	char szName[MAX_NAME_LENGTH * 2 + 1];
	g_dDb.Escape(szUName, szName, MAX_NAME_LENGTH * 2 + 1);

	// Packing required information for later
	Handle pack = CreateDataPack();
	WritePackFloat(pack, g_fFinalTime[client]);
	WritePackCell(pack, GetClientUserId(client));

	char szQuery[1024];
	// "UPDATE ck_playertimes SET name = '%s', runtimepro = '%f', velStartXY = %i, velStartXYZ = %i, velStartZ = %i, velEndXY = %i, velEndXYZ = %i, velEndZ = %i WHERE steamid = '%s' AND mapname = '%s' AND style = %i;";
	Format(szQuery, sizeof(szQuery), sql_updateRecordPro, szName, g_fFinalTime[client], g_iStartVelsNew[client][0][0], g_iStartVelsNew[client][0][1], g_iStartVelsNew[client][0][2], g_iEndVelsNew[client][0][0], g_iEndVelsNew[client][0][1], g_iEndVelsNew[client][0][2], g_szSteamID[client], g_szMapName, 0);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_updateRecordPro - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_UpdateRecordProCallback, szQuery, pack, DBPrio_Low);
}


public void SQL_UpdateRecordProCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_UpdateRecordProCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	float time = ReadPackFloat(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	delete pack;

	if (IsValidClient(client))
	{
		// Find out how many times are are faster than the players time
		char szQuery[512];
		Format(szQuery, sizeof(szQuery), "SELECT count(runtimepro) FROM `ck_playertimes` WHERE `mapname` = '%s' AND `runtimepro` < %f-(1E-3) AND style = 0;", g_szMapName, time);
		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "SQL_UpdateRecordProCallback - szQuery: %s", szQuery);
		}
		g_dDb.Query(SQL_UpdateRecordProCallback2, szQuery, GetClientUserId(client), DBPrio_Low);
	}
}

public void SQL_UpdateRecordProCallback2(Database db, DBResultSet results, const char[] error, int userid)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[Surftimer] SQL Error (SQL_UpdateRecordProCallback2): %s", error);
		return;
	}

	int client = GetClientOfUserId(userid);

	if (IsValidClient(client))
	{
		// Get players rank, 9999999 = error
		int rank = 9999999;
		if (results.HasResults && results.FetchRow())
		{
			rank = (results.FetchInt(0)+1);
		}
		g_MapRank[client] = rank;
		
		for (int i = 0; i < 3; i ++)
			g_iStartVelsRecord[client][0][i] = g_iStartVelsNew[client][0][i];

		if (rank <= 10 && rank > 1)
			g_bTop10Time[client] = true;
		else
			g_bTop10Time[client] = false;

		MapFinishedMsgs(client);

		if (g_bInsertNewTime)
		{
			db_selectCurrentMapImprovement();
			g_bInsertNewTime = false;
		}
	}
}

public void db_viewAllRecords(int client, char szSteamId[32])
{
	// "SELECT db1.name, db2.steamid, db2.mapname, db2.runtimepro as overall, db1.steamid, db3.tier FROM ck_playertimes as db2 INNER JOIN ck_playerrank as db1 on db2.steamid = db1.steamid INNER JOIN ck_maptier AS db3 ON db2.mapname = db3.mapname WHERE db2.steamid = '%s' AND db2.style = %i AND db1.style = %i AND db2.runtimepro > -1.0 ORDER BY mapname ASC;";

	char szQuery[1024];
	Format(szQuery, sizeof(szQuery), sql_selectPersonalAllRecords, szSteamId, g_ProfileStyleSelect[client], g_ProfileStyleSelect[client]);

	if ((StrContains(szSteamId, "STEAM_") != -1))
	{
		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "db_viewAllRecords - szQuery: %s", szQuery);
		}
		g_dDb.Query(SQL_ViewAllRecordsCallback, szQuery, GetClientUserId(client), DBPrio_Low);
	}
	else if (IsClientInGame(client))
		CPrintToChat(client, "%t", "SQL3", g_szChatPrefix);
}


public void SQL_ViewAllRecordsCallback(Database db, DBResultSet results, const char[] error, int userid)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_ViewAllRecordsCallback): %s", error);
		return;
	}

	int bHeader = false;
	char szUncMaps[1024];
	int mapcount = 0;
	char szName[MAX_NAME_LENGTH];
	char szSteamId[32];

	int client = GetClientOfUserId(userid);

	if (IsValidClient(client))
	{
		if (results.HasResults)
		{
			float time;
			char szMapName[128];
			char szMapName2[128];
			char szQuery[1024];
			Format(szUncMaps, sizeof(szUncMaps), "");
			g_totalMapsCompleted[client] = results.RowCount;

			g_CompletedMenu = CreateMenu(FinishedMapsMenuHandler);
			SetMenuPagination(g_CompletedMenu, 5);
			g_mapsCompletedLoop[client] = 0;

			while (results.FetchRow())
			{
				results.FetchString(0, szName, MAX_NAME_LENGTH);
				results.FetchString(1, szSteamId, MAX_NAME_LENGTH);
				results.FetchString(2, szMapName, 128);

				time = results.FetchFloat(3);

				int tier = results.FetchInt(5);

				int mapfound = false;

				// map in rotation?
				for (int i = 0; i < GetArraySize(g_MapList); i++)
				{
					GetArrayString(g_MapList, i, szMapName2, sizeof(szMapName2));
					if (StrEqual(szMapName2, szMapName, false))
					{
						if (!bHeader)
						{
							PrintToConsole(client, " ");
							PrintToConsole(client, "-------------");
							PrintToConsole(client, "Finished Maps");
							PrintToConsole(client, "Player: %s", szName);
							PrintToConsole(client, "SteamID: %s", szSteamId);
							PrintToConsole(client, "-------------");
							PrintToConsole(client, " ");
							bHeader = true;
							CPrintToChat(client, "%t", "ConsoleOutput", g_szChatPrefix);
						}
						Handle pack = CreateDataPack();
						WritePackString(pack, szName);
						WritePackString(pack, szSteamId);
						WritePackString(pack, szMapName);
						WritePackFloat(pack, time);
						WritePackCell(pack, GetClientUserId(client));
						WritePackCell(pack, tier);
						Format(szQuery, sizeof(szQuery), sql_selectPlayerRankProTime, szSteamId, szMapName, szMapName);
						if (g_cLogQueries.BoolValue)
						{
							LogToFile(g_szQueryFile, "SQL_ViewAllRecordsCallback - szQuery: %s", szQuery);
						}
						g_dDb.Query(SQL_ViewAllRecordsCallback2, szQuery, pack, DBPrio_Low);
						mapfound = true;
						continue;
					}
				}
				if (!mapfound)
				{
					mapcount++;
					g_uncMapsCompleted[client] = mapcount;
					if (!mapfound && mapcount == 1)
					{
						Format(szUncMaps, sizeof(szUncMaps), "%s", szMapName);
					}
					else
					{
						if (!mapfound && mapcount > 1)
						{
							Format(szUncMaps, sizeof(szUncMaps), "%s, %s", szUncMaps, szMapName);
						}
					}
				}
			}
		}
		if (!StrEqual(szUncMaps, ""))
		{
			if (!bHeader)
			{
				CPrintToChat(client, "%t", "ConsoleOutput", g_szChatPrefix);
				PrintToConsole(client, " ");
				PrintToConsole(client, "-------------");
				PrintToConsole(client, "Finished Maps");
				PrintToConsole(client, "Player: %s", szName);
				PrintToConsole(client, "SteamID: %s", szSteamId);
				PrintToConsole(client, "-------------");
				PrintToConsole(client, " ");
			}
			PrintToConsole(client, "Times on maps which are not in the mapcycle.txt (Records still count but you dont get points): %s", szUncMaps);
		}
		if (!bHeader && StrEqual(szUncMaps, ""))
		{
			ProfileMenu2(client, g_ProfileStyleSelect[client], "", g_szSteamID[client]);
			CPrintToChat(client, "%t", "PlayerHasNoMapRecords", g_szChatPrefix, g_szProfileName[client]);
		}
	}
}

public void SQL_ViewAllRecordsCallback2(Database db, DBResultSet results, const char[] error, any pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_ViewAllRecordsCallback2): %s", error);
		return;
	}

	if (results.HasResults && results.FetchRow())
	{
		char szQuery[512];
		char szName[MAX_NAME_LENGTH];
		char szSteamId[32];
		char szMapName[128];

		int rank = results.FetchInt(0);

		WritePackCell(pack, rank);
		ResetPack(pack);
		ReadPackString(pack, szName, MAX_NAME_LENGTH);
		ReadPackString(pack, szSteamId, 32);
		ReadPackString(pack, szMapName, 128);

		Format(szQuery, sizeof(szQuery), sql_selectPlayerProCount, szMapName);
		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "SQL_ViewAllRecordsCallback2 - szQuery: %s", szQuery);
		}
		g_dDb.Query(SQL_ViewAllRecordsCallback3, szQuery, pack, DBPrio_Low);
	}
}

public void SQL_ViewAllRecordsCallback3(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_ViewAllRecordsCallback3): %s", error);
		delete pack;
		return;
	}

	// fluffys

	// if there is a player record
	if (results.HasResults && results.FetchRow())
	{
		int count = results.FetchInt(1);
		char szTime[32];
		char szMapName[128];
		char szSteamId[32];
		char szName[MAX_NAME_LENGTH];
		// fluffys
		char szValue[128];

		ResetPack(pack);
		ReadPackString(pack, szName, MAX_NAME_LENGTH);
		ReadPackString(pack, szSteamId, 32);
		ReadPackString(pack, szMapName, 128);
		float time = ReadPackFloat(pack);
		int client = GetClientOfUserId(ReadPackCell(pack));
		int tier = ReadPackCell(pack);
		int rank = ReadPackCell(pack);
		delete pack;

		if (IsValidClient(client))
		{
			FormatTimeFloat(client, time, 3, szTime, sizeof(szTime));

			if (time < 3600.0)
			Format(szTime, 32, "%s", szTime);

			char szS[32];
			char szT[32];
			char szTotal[32];
			IntToString(rank, szT, sizeof(szT));
			IntToString(count, szS, sizeof(szS));
			Format(szTotal, sizeof(szTotal), "%s%s", szT, szS);
			if (strlen(szTotal) == 8)
				Format(szValue, 128, "%i/%i    %s | » %s - %i", rank, count, szTime, szMapName, tier);
			else if (strlen(szTotal) == 7)
				Format(szValue, 128, "%i/%i      %s | » %s - %i", rank, count, szTime, szMapName, tier);
			else if (strlen(szTotal) == 6)
				Format(szValue, 128, "%i/%i      %s | » %s - %i", rank, count, szTime, szMapName, tier);
			else if (strlen(szTotal) == 5)
				Format(szValue, 128, "%i/%i      %s | » %s - %i", rank, count, szTime, szMapName, tier);
			else if (strlen(szTotal) == 4)
				Format(szValue, 128, "%i/%i        %s | » %s - %i", rank, count, szTime, szMapName, tier);
			else if (strlen(szTotal) == 3)
				Format(szValue, 128, "%i/%i          %s | » %s - %i", rank, count, szTime, szMapName, tier);
			else if (strlen(szTotal) == 2)
				Format(szValue, 128, "%i/%i           %s | » %s - %i", rank, count, szTime, szMapName, tier);
			else if (strlen(szTotal) == 1)
				Format(szValue, 128, "%i/%i            %s | » %s - %i", rank, count, szTime, szMapName, tier);
			else
				Format(szValue, 128, "%i/%i  %s | » %s - %i", rank, count, szTime, szMapName, tier);

			g_mapsCompletedLoop[client]++;
			AddMenuItem(g_CompletedMenu, szSteamId, szValue, ITEMDRAW_DISABLED);
			int totalMaps = g_totalMapsCompleted[client] - g_uncMapsCompleted[client];

			if (g_mapsCompletedLoop[client] == totalMaps)
			{
				char title[256];
				Format(title, 256, "%i Finished maps for %s \n    Rank          Time          Mapname - Tier", totalMaps, szName);
				SetMenuTitle(g_CompletedMenu, title);
				SetMenuOptionFlags(g_CompletedMenu, MENUFLAG_BUTTON_EXIT);
				DisplayMenu(g_CompletedMenu, client, MENU_TIME_FOREVER);
			}

			PrintToConsole(client, "%s - Tier: %i, Time: %s, Rank: %i/%i", szMapName, tier, szTime, rank, count);
		}
	}
}

public void db_viewTop10Records(int client, char szSteamId[32], int type)
{
	// "SELECT db1.name, db2.steamid, db2.mapname, db2.runtimepro as overall, db1.steamid, db3.tier FROM ck_playertimes as db2 INNER JOIN ck_playerrank as db1 on db2.steamid = db1.steamid INNER JOIN ck_maptier AS db3 ON db2.mapname = db3.mapname WHERE db2.steamid = '%s' AND db2.style = %i AND db1.style = %i AND db2.runtimepro > -1.0 ORDER BY mapname ASC;";

	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, type);

	char szQuery[1024];
	Format(szQuery, sizeof(szQuery), sql_selectPersonalAllRecords, szSteamId, g_ProfileStyleSelect[client], g_ProfileStyleSelect[client]);

	if ((StrContains(szSteamId, "STEAM_") != -1))
	{
		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "db_viewTop10Records - szQuery: %s", szQuery);
		}
		g_dDb.Query(SQL_ViewTop10RecordsCallback, szQuery, pack, DBPrio_Low);
	}
	else if (IsClientInGame(client))
		CPrintToChat(client, "%t", "SQL3", g_szChatPrefix);
}

public void SQL_ViewTop10RecordsCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_ViewAllRecordsCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int type = ReadPackCell(pack);
	delete pack;

	if (IsValidClient(client))
	{
		int bHeader = false;
		char szUncMaps[1024];
		int mapcount = 0;
		char szName[MAX_NAME_LENGTH];
		char szSteamId[32];
		if (results.HasResults)
		{
			float time;
			char szMapName[128];
			char szMapName2[128];
			char szQuery[1024];
			Format(szUncMaps, sizeof(szUncMaps), "");
			while (results.FetchRow())
			{
				results.FetchString(0, szName, MAX_NAME_LENGTH);
				results.FetchString(1, szSteamId, MAX_NAME_LENGTH);
				results.FetchString(2, szMapName, 128);

				time = results.FetchFloat(3);

				int mapfound = false;

				// map in rotation?
				for (int i = 0; i < GetArraySize(g_MapList); i++)
				{
					GetArrayString(g_MapList, i, szMapName2, sizeof(szMapName2));
					if (StrEqual(szMapName2, szMapName, false))
					{
						if (!bHeader)
						{
							PrintToConsole(client, " ");
							PrintToConsole(client, "-------------");
							if (type == 0)
								PrintToConsole(client, "Top 10 Maps");
							else
								PrintToConsole(client, "World Records");
							PrintToConsole(client, "Player: %s", szName);
							PrintToConsole(client, "SteamID: %s", szSteamId);
							PrintToConsole(client, "-------------");
							PrintToConsole(client, " ");
							bHeader = true;
							CPrintToChat(client, "%t", "ConsoleOutput", g_szChatPrefix);
						}
						Handle pack2 = CreateDataPack();
						WritePackString(pack2, szName);
						WritePackString(pack2, szSteamId);
						WritePackString(pack2, szMapName);
						WritePackFloat(pack2, time);
						WritePackCell(pack2, GetClientUserId(client));
						WritePackCell(pack2, type);

						Format(szQuery, sizeof(szQuery), sql_selectPlayerRankProTime, szSteamId, szMapName, szMapName);
						if (g_cLogQueries.BoolValue)
						{
							LogToFile(g_szQueryFile, "SQL_ViewTop10RecordsCallback - szQuery: %s", szQuery);
						}
						g_dDb.Query(SQL_ViewTop10RecordsCallback2, szQuery, pack2, DBPrio_Low);
						mapfound = true;
						continue;
					}
				}
				if (!mapfound)
				{
					mapcount++;
					if (!mapfound && mapcount == 1)
					{
						Format(szUncMaps, sizeof(szUncMaps), "%s", szMapName);
					}
					else
					{
						if (!mapfound && mapcount > 1)
						{
							Format(szUncMaps, sizeof(szUncMaps), "%s, %s", szUncMaps, szMapName);
						}
					}
				}
			}
		}
		if (!StrEqual(szUncMaps, ""))
		{
			if (!bHeader)
			{
				CPrintToChat(client, "%t", "ConsoleOutput", g_szChatPrefix);
				PrintToConsole(client, " ");
				PrintToConsole(client, "-------------");
				if (type == 0)
					PrintToConsole(client, "Top 10 Maps");
				else
					PrintToConsole(client, "World Records");
				PrintToConsole(client, "Player: %s", szName);
				PrintToConsole(client, "SteamID: %s", szSteamId);
				PrintToConsole(client, "-------------");
				PrintToConsole(client, " ");
			}
			PrintToConsole(client, "Times on maps which are not in the mapcycle.txt (Records still count but you dont get points): %s", szUncMaps);
		}
		if (!bHeader && StrEqual(szUncMaps, ""))
		{
			ProfileMenu2(client, g_ProfileStyleSelect[client], "", g_szSteamID[client]);
			CPrintToChat(client, "%t", "PlayerHasNoMapRecords", g_szChatPrefix, g_szProfileName[client]);
		}
	}
}

public void SQL_ViewTop10RecordsCallback2(Database db, DBResultSet results, const char[] error, any pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_ViewTop10RecordsCallback2): %s", error);
		return;
	}

	if (results.HasResults && results.FetchRow())
	{
		char szQuery[512];
		char szName[MAX_NAME_LENGTH];
		char szSteamId[32];
		char szMapName[128];

		int rank = results.FetchInt(0);

		WritePackCell(pack, rank);
		ResetPack(pack);
		ReadPackString(pack, szName, MAX_NAME_LENGTH);
		ReadPackString(pack, szSteamId, 32);
		ReadPackString(pack, szMapName, 128);

		Format(szQuery, sizeof(szQuery), sql_selectPlayerProCount, szMapName);
		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "SQL_ViewTop10RecordsCallback2 - szQuery: %s", szQuery);
		}
		g_dDb.Query(SQL_ViewTop10RecordsCallback3, szQuery, pack, DBPrio_Low);
	}
}

public void SQL_ViewTop10RecordsCallback3(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_ViewAllRecordsCallback3): %s", error);
		delete pack;
		return;
	}

	// fluffys

	int i = 1;

	// if there is a player record
	if (results.HasResults && results.FetchRow())
	{
		int count = results.RowCount;
		char szTime[32];
		char szMapName[128];
		char szSteamId[32];
		char szName[MAX_NAME_LENGTH];
		// fluffys
		char szValue[128];

		ResetPack(pack);
		ReadPackString(pack, szName, MAX_NAME_LENGTH);
		ReadPackString(pack, szSteamId, 32);
		ReadPackString(pack, szMapName, 128);
		float time = ReadPackFloat(pack);
		int client = GetClientOfUserId(ReadPackCell(pack));
		int type = ReadPackCell(pack);
		int rank = ReadPackCell(pack);
		delete pack;

		FormatTimeFloat(client, time, 3, szTime, sizeof(szTime));

		if (IsValidClient(client))
		{
			if (time < 3600.0)
			{
				Format(szTime, 32, "   %s", szTime);
			}

			Format(szValue, 128, "%i/%i %s |    » %s", rank, count, szTime, szMapName);
			i++;

			
			if (type == 0)
			{
				if (rank <= 10)
					PrintToConsole(client, "%s, Time: %s, Rank: %i/%i", szMapName, szTime, rank, count);
			}
			else
			{
				if (rank == 1)
					PrintToConsole(client, "%s, Time: %s, Rank: %i/%i", szMapName, szTime, rank, count);
			}
		}
	}
}

// Getting player settings starts here
public void db_viewPersonalRecords(int client, char szSteamId[32], char szMapName[128])
{
	char szName[32];
	GetClientName(client, szName, sizeof(szName));
	g_fClientsLoading[client][0] = GetGameTime();
	LogToFileEx(g_szLogFile, "[Surftimer] Loading %s - %s settings", szSteamId, szName);

	g_fTick[client][0] = GetGameTime();

	char szQuery[1024];
	Format(szQuery, sizeof(szQuery), sql_selectPersonalRecords, szSteamId, szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewPersonalRecords - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_selectPersonalRecordsCallback, szQuery, GetClientUserId(client), DBPrio_Low);
}


public void SQL_selectPersonalRecordsCallback(Database db, DBResultSet results, const char[] error, any userid)
{
	int client = GetClientOfUserId(userid);

	if (IsValidClient(client))
	{
		if (!IsValidDatabase(db, error))
		{
			if (StrContains(error, "Unknown column", false) != -1)
			{
				LogError("[Surftimer] (SQL_selectPersonalRecordsCallback) Your database are not up to date! Please use the command \"sm_surftimer_upgrade\" to upgrade your database.");
			}
			else
			{
				LogError("[Surftimer] SQL Error (SQL_selectPersonalRecordsCallback): %s", error);
			}

			if (!g_bSettingsLoaded[client])
				LoadClientSetting(client, g_iSettingToLoad[client]);
			return;
		}

		g_fPersonalRecord[client] = 0.0;
		Format(g_szPersonalRecord[client], 64, "NONE");
		for (int i = 1; i < MAX_STYLES; i++)
		{
			Format(g_szPersonalStyleRecord[i][client], 64, "NONE");
			g_fPersonalStyleRecord[i][client] = 0.0;
		}

		for (int i = 0; i < 3; i++)
			g_iStartVelsRecord[client][0][i] = 0;

		if (results.HasResults)
		{
			int style;
			while (results.FetchRow())
			{
				style = results.FetchInt(1);
				if (style == 0)
				{
					g_fPersonalRecord[client] = results.FetchFloat(0);

					g_iStartVelsRecord[client][0][0] = results.FetchInt(2);
					g_iStartVelsRecord[client][0][1] = results.FetchInt(3);
					g_iStartVelsRecord[client][0][2] = results.FetchInt(4);

					if (g_fPersonalRecord[client] > 0.0)
					{
						FormatTimeFloat(client, g_fPersonalRecord[client], 3, g_szPersonalRecord[client], 64);
						// Time found, get rank in current map
						db_viewMapRankPro(client);
					}
				}
				else
				{
					g_fPersonalStyleRecord[style][client] = results.FetchFloat(0);

					if (g_fPersonalStyleRecord[style][client] > 0.0)
					{
						FormatTimeFloat(client, g_fPersonalStyleRecord[style][client], 3, g_szPersonalStyleRecord[style][client], 64);
						// Time found, get rank in current map
						db_viewStyleMapRank(client, style);
					}
				}
			}
		}
		else
		{
			Format(g_szPersonalRecord[client], 64, "NONE");
			g_fPersonalRecord[client] = 0.0;

			for (int i = 1; i < MAX_STYLES; i++)
			{
				Format(g_szPersonalStyleRecord[i][client], 64, "NONE");
				g_fPersonalStyleRecord[i][client] = 0.0;
			}
		}

		if (!g_bSettingsLoaded[client])
		{
			g_fTick[client][1] = GetGameTime();
			float tick = g_fTick[client][1] - g_fTick[client][0];
			LogToFileEx(g_szLogFile, "[Surftimer] %s: Finished db_viewPersonalRecords in %fs", g_szSteamID[client], tick);
			g_fTick[client][0] = GetGameTime();
			LoadClientSetting(client, g_iSettingToLoad[client]);
		}
	}
}

/*===================================
=            PLAYER TEMP            =
===================================*/

public void db_deleteTmp(int client)
{
	char szQuery[256];
	if (!IsValidClient(client))
		return;
	Format(szQuery, sizeof(szQuery), sql_deletePlayerTmp, g_szSteamID[client]);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_deleteTmp - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_CheckCallback, szQuery, _, DBPrio_Low);
}

public void db_selectLastRun(int client)
{
	char szQuery[512];
	if (!IsValidClient(client))
	return;
	Format(szQuery, sizeof(szQuery), sql_selectPlayerTmp, g_szSteamID[client], g_szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectLastRun - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_LastRunCallback, szQuery, GetClientUserId(client), DBPrio_Low);
}

public void SQL_LastRunCallback(Database db, DBResultSet results, const char[] error, int userid)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_LastRunCallback): %s", error);
		return;
	}

	

	int client = GetClientOfUserId(userid);
	
	g_bTimerRunning[client] = false;
	if (results.HasResults && results.FetchRow() && IsValidClient(client))
	{

		// "SELECT cords1,cords2,cords3, angle1, angle2, angle3,runtimeTmp, EncTickrate, Stage, zonegroup FROM ck_playertemp WHERE steamid = '%s' AND mapname = '%s';";

		// Get last psition
		g_fPlayerCordsRestore[client][0] = results.FetchFloat(0);
		g_fPlayerCordsRestore[client][1] = results.FetchFloat(1);
		g_fPlayerCordsRestore[client][2] = results.FetchFloat(2);
		g_fPlayerAnglesRestore[client][0] = results.FetchFloat(3);
		g_fPlayerAnglesRestore[client][1] = results.FetchFloat(4);
		g_fPlayerAnglesRestore[client][2] = results.FetchFloat(5);


		int zGroup;
		zGroup = results.FetchInt(9);

		g_iClientInZone[client][2] = zGroup;

		g_Stage[zGroup][client] = results.FetchInt(8);

		// Set new start time
		float fl_time = results.FetchFloat(6);
		int tickrate = RoundFloat(float(results.FetchInt(7)) / 5.0 / 11.0);
		if (tickrate == g_Server_Tickrate)
		{
			if (fl_time > 0.0)
			{
				g_fStartTime[client] = GetGameTime() - fl_time;
				g_bTimerRunning[client] = true;
			}

			if (results.FetchFloat(0) == -1.0 && results.FetchFloat(1) == -1.0 && results.FetchFloat(2) == -1.0)
			{
				g_bRestorePosition[client] = false;
				g_bRestorePositionMsg[client] = false;
			}
			else
			{
				if (g_bLateLoaded && IsPlayerAlive(client) && !g_specToStage[client])
				{
					g_bPositionRestored[client] = true;
					TeleportEntity(client, g_fPlayerCordsRestore[client], g_fPlayerAnglesRestore[client], NULL_VECTOR);
					g_bRestorePosition[client] = false;
				}
				else
				{
					g_bRestorePosition[client] = true;
					g_bRestorePositionMsg[client] = true;
				}

			}
		}
	}
	else
	{

		g_bTimerRunning[client] = false;
	}
}

/*===================================
=            CHECKPOINTS            =
===================================*/

public void db_viewRecordCheckpointInMap()
{
	for (int k = 0; k < MAXZONEGROUPS; k++)
	{
		g_bCheckpointRecordFound[k] = false;
		for (int i = 0; i < CPLIMIT; i++)
		g_fCheckpointServerRecord[k][i] = 0.0;
	}
	// "SELECT c.zonegroup, c.cp1, c.cp2, c.cp3, c.cp4, c.cp5, c.cp6, c.cp7, c.cp8, c.cp9, c.cp10, c.cp11, c.cp12, c.cp13, c.cp14, c.cp15, c.cp16, c.cp17, c.cp18, c.cp19, c.cp20, c.cp21, c.cp22, c.cp23, c.cp24, c.cp25, c.cp26, c.cp27, c.cp28, c.cp29, c.cp30, c.cp31, c.cp32, c.cp33, c.cp34, c.cp35 FROM ck_checkpoints c WHERE steamid = '%s' AND mapname='%s' UNION SELECT a.zonegroup, b.cp1, b.cp2, b.cp3, b.cp4, b.cp5, b.cp6, b.cp7, b.cp8, b.cp9, b.cp10, b.cp11, b.cp12, b.cp13, b.cp14, b.cp15, b.cp16, b.cp17, b.cp18, b.cp19, b.cp20, b.cp21, b.cp22, b.cp23, b.cp24, b.cp25, b.cp26, b.cp27, b.cp28, b.cp29, b.cp30, b.cp31, b.cp32, b.cp33, b.cp34, b.cp35 FROM ck_bonus a LEFT JOIN ck_checkpoints b ON a.steamid = b.steamid AND a.zonegroup = b.zonegroup WHERE a.mapname = '%s' GROUP BY a.zonegroup";
	
	// SELECT steamid, mapname, cp, time, zonegroup FROM ck_checkpoints WHERE steamid = '%s' AND mapname = '%s' AND zonegroup = 0;
	char szQuery[1028];
	Format(szQuery, sizeof(szQuery), sql_selectRecordCheckpoints, g_szRecordMapSteamID, g_szMapName, g_szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewRecordCheckpointInMap - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_selectRecordCheckpointsCallback, szQuery, _, DBPrio_Low);
}

public void sql_selectRecordCheckpointsCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		if (StrContains(error, "Unknown column", false) != -1)
		{
			LogError("[Surftimer] (sql_selectRecordCheckpointsCallback) Your database are not up to date! Please use the command \"sm_surftimer_upgrade\" to upgrade your database.");
		}
		else
		{
			LogError("[Surftimer] SQL Error (sql_selectRecordCheckpointsCallback): %s", error);
		}

		if (!g_bServerDataLoaded)
			db_CalcAvgRunTime();
		return;
	}

	if (results.HasResults)
	{
		int zonegroup, cp, index;
		while (results.FetchRow())
		{
			cp = results.FetchInt(2);
			index = cp - 1;
			zonegroup = results.FetchInt(10);
			g_fCheckpointServerRecord[zonegroup][index] = results.FetchFloat(3);
			g_iCheckpointVelsStartServerRecord[zonegroup][index][0] = results.FetchInt(4);
			g_iCheckpointVelsStartServerRecord[zonegroup][index][1] = results.FetchInt(5);
			g_iCheckpointVelsStartServerRecord[zonegroup][index][2] = results.FetchInt(6);
			g_iCheckpointVelsEndServerRecord[zonegroup][index][0] = results.FetchInt(7);
			g_iCheckpointVelsEndServerRecord[zonegroup][index][1] = results.FetchInt(8);
			g_iCheckpointVelsEndServerRecord[zonegroup][index][2] = results.FetchInt(9);
			if (!g_bCheckpointRecordFound[zonegroup] && g_fCheckpointServerRecord[zonegroup][index] > 0.0)
				g_bCheckpointRecordFound[zonegroup] = true;
		}
	}

	if (!g_bServerDataLoaded)
		db_CalcAvgRunTime();

	return;
}

public void db_viewCheckpoints(int client, char szSteamID[32], char szMapName[128])
{
	char szQuery[1024];
	Format(szQuery, sizeof(szQuery), sql_selectCheckpoints, szMapName, szSteamID);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewCheckpoints - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_selectCheckpointsCallback, szQuery, GetClientUserId(client), DBPrio_Low);
}

public void SQL_selectCheckpointsCallback(Database db, DBResultSet results, const char[] error, any userid)
{
	// fluffys come back
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_selectCheckpointsCallback): %s", error);
		return;
	}

	int zoneGrp, cp, index;

	int client = GetClientOfUserId(userid);

	if (!IsValidClient(client))
		return;

	if (results.HasResults)
	{
		// SELECT zonegroup, cp, time FROM ck_checkpoints WHERE mapname='%s' AND steamid = '%s' AND zonegroup = 0;
		while (results.FetchRow())
		{
			zoneGrp = results.FetchInt(0);
			cp = results.FetchInt(1);
			index = cp - 1;
			g_bCheckpointsFound[zoneGrp][client] = true;
			g_fCheckpointTimesRecord[zoneGrp][client][index] = results.FetchFloat(2);
			// 0 = XY, 1 = XYZ, 2 = Z
			g_iCheckpointVelsStartRecord[zoneGrp][client][index][0] = results.FetchInt(3);
			g_iCheckpointVelsStartRecord[zoneGrp][client][index][1] = results.FetchInt(4);
			g_iCheckpointVelsStartRecord[zoneGrp][client][index][2] = results.FetchInt(5);
			g_iCheckpointVelsEndRecord[zoneGrp][client][index][0] = results.FetchInt(6);
			g_iCheckpointVelsEndRecord[zoneGrp][client][index][1] = results.FetchInt(7);
			g_iCheckpointVelsEndRecord[zoneGrp][client][index][2] = results.FetchInt(8);
			g_iCheckpointVelsAvgRecord[zoneGrp][client][index][0] = results.FetchInt(9);
			g_iCheckpointVelsAvgRecord[zoneGrp][client][index][1] = results.FetchInt(10);
			g_iCheckpointVelsAvgRecord[zoneGrp][client][index][2] = results.FetchInt(11);
		}
	}

	if (!g_bSettingsLoaded[client])
	{
		g_fTick[client][1] = GetGameTime();
		float tick = g_fTick[client][1] - g_fTick[client][0];
		LogToFileEx(g_szLogFile, "[SurfTimer] %s: Finished db_viewCheckpoints in %fs", g_szSteamID[client], tick);

		float time = g_fTick[client][1] - g_fClientsLoading[client][0];
		char szName[32];
		GetClientName(client, szName, sizeof(szName));
		LogToFileEx(g_szLogFile, "[SurfTimer] Finished loading %s - %s settings in %fs", g_szSteamID[client], szName, time);
		
		// Print a VIP's custom join msg to all
		if (g_bEnableJoinMsgs && !StrEqual(g_szCustomJoinMsg[client], "none") && IsPlayerVip(client, true, false))
			CPrintToChatAll("%s", g_szCustomJoinMsg[client]);

		// CalculatePlayerRank(client);
		g_bSettingsLoaded[client] = true;
		g_bLoadingSettings[client] = false;

		db_UpdateLastSeen(client);

		if (GetConVarBool(g_hTeleToStartWhenSettingsLoaded))
		{
			Command_Restart(client, 1);
			CreateTimer(0.1, RestartPlayer, GetClientUserId(client));
		}

		// Seach for next client to load
		for (int i = 1; i <= MAXPLAYERS; i++)
		{
			if (IsValidClient(i) && !IsFakeClient(i) && !g_bSettingsLoaded[i] && !g_bLoadingSettings[i])
			{
				char szSteamID[32];
				GetClientAuthId(i, AuthId_Steam2, szSteamID, 32, true);
				g_iSettingToLoad[i] = 0;
				LoadClientSetting(i, g_iSettingToLoad[i]);
				g_bLoadingSettings[i] = true;
				break;
			}
		}
	}
}

public void db_viewCheckpointsinZoneGroup(int client, char szSteamID[32], char szMapName[128], int zonegroup)
{
	char szQuery[1024];
	// "SELECT cp1, cp2, cp3, cp4, cp5, cp6, cp7, cp8, cp9, cp10, cp11, cp12, cp13, cp14, cp15, cp16, cp17, cp18, cp19, cp20, cp21, cp22, cp23, cp24, cp25, cp26, cp27, cp28, cp29, cp30, cp31, cp32, cp33, cp34, cp35 FROM ck_checkpoints WHERE mapname='%s' AND steamid = '%s' AND zonegroup = %i;";

	// SELECT zonegroup, cp, time, velStartXY, velStartXYZ, velStartZ, velEndXY, velEndXYZ, velEndZ, velAvgXY, velAvgXYZ, velAvgZ FROM ck_checkpoints WHERE mapname='%s' AND steamid = '%s' AND zonegroup = %d;
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, zonegroup);

	Format(szQuery, sizeof(szQuery), sql_selectCheckpointsinZoneGroup, szMapName, szSteamID, zonegroup);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewCheckpointsinZoneGroup - szQuery: %s", szQuery);
	}
	g_dDb.Query(db_viewCheckpointsinZoneGroupCallback, szQuery, pack, DBPrio_Low);
}

public void db_viewCheckpointsinZoneGroupCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[Surftimer] SQL Error (SQL_selectCheckpointsCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int zonegrp = ReadPackCell(pack);
	delete pack;

	if (!IsValidClient(client))
	{
		return;
	}

	if (results.HasResults)
	{
		int cp, index;
		while (results.FetchRow())
		{
			cp = results.FetchInt(1);
			index = cp - 1;
			g_bCheckpointsFound[zonegrp][client] = true;
			g_fCheckpointTimesRecord[zonegrp][client][index] = results.FetchFloat(2);
			// 0 = XY, 1 = XYZ, 2 = Z
			g_iCheckpointVelsStartRecord[zonegrp][client][index][0] = results.FetchInt(3);
			g_iCheckpointVelsStartRecord[zonegrp][client][index][1] = results.FetchInt(4);
			g_iCheckpointVelsStartRecord[zonegrp][client][index][2] = results.FetchInt(5);
			g_iCheckpointVelsEndRecord[zonegrp][client][index][0] = results.FetchInt(6);
			g_iCheckpointVelsEndRecord[zonegrp][client][index][1] = results.FetchInt(7);
			g_iCheckpointVelsEndRecord[zonegrp][client][index][2] = results.FetchInt(8);
			g_iCheckpointVelsAvgRecord[zonegrp][client][index][0] = results.FetchInt(9);
			g_iCheckpointVelsAvgRecord[zonegrp][client][index][1] = results.FetchInt(10);
			g_iCheckpointVelsAvgRecord[zonegrp][client][index][2] = results.FetchInt(11);
		}
	}
	else
	{
		g_bCheckpointsFound[zonegrp][client] = false;
	}
}

public void db_UpdateCheckpoints(int client, char szSteamID[32], int zGroup)
{
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, zGroup);
	// char sql_updateCheckpoint[] = "UPDATE ck_checkpoints SET time = '%f', velStartXY = %d, velStartXYZ = %d, velStartZ = %d, velEndXY = %d, velEndXYZ = %d, velEndZ = %d, velAvgXY = %d, velAvgXYZ = %d, velAvgZ = %d, WHERE steamid = '%s' AND mapname = '%s' AND cp = %d AND zonegroup = %d;";
	if (g_bCheckpointsFound[zGroup][client])
	{
		char szQuery[1024];
		Transaction tTransaction = new Transaction();
		int cp;
		for (int i = 0; i < CPLIMIT; i++)
		{
			if (g_fCheckpointTimesNew[zGroup][client][i] <= 0.0)
				continue;

			cp = i + 1;
			Format(szQuery, sizeof(szQuery), sql_updateCheckpoint, g_fCheckpointTimesNew[zGroup][client][i], g_iCheckpointVelsStartNew[zGroup][client][i][0], g_iCheckpointVelsStartNew[zGroup][client][i][1], g_iCheckpointVelsStartNew[zGroup][client][i][2], g_iCheckpointVelsEndNew[zGroup][client][i][0], g_iCheckpointVelsEndNew[zGroup][client][i][1], g_iCheckpointVelsEndNew[zGroup][client][i][2], 0, 0, 0, szSteamID, g_szMapName, cp, zGroup);
			tTransaction.AddQuery(szQuery);
		}
		g_dDb.Execute(tTransaction, SQLTxn_UpdateCheckpointsSuccess, SQLTxn_UpdateCheckpointsFailed, pack);
	}
	else
	{
		// char sql_insertCheckpoint[] = "INSERT INTO ck_checkpoints VALUES ('%s', '%s', '%d', '%f', '%d', '%d', '%d', '%d', '%d', '%d', '%d', '%d', '%d', %d');";
		char szQuery[1024];
		int cp;
		Transaction tTransaction = new Transaction();

		for (int i = 0; i < CPLIMIT; i++)
		{
			if (g_fCheckpointTimesNew[zGroup][client][i] <= 0.0)
				continue;
			cp = i + 1;
			Format(szQuery, sizeof(szQuery), sql_insertCheckpoint, szSteamID, g_szMapName, cp, g_fCheckpointTimesNew[zGroup][client][i], g_iCheckpointVelsStartNew[zGroup][client][i][0], g_iCheckpointVelsStartNew[zGroup][client][i][1], g_iCheckpointVelsStartNew[zGroup][client][i][2], g_iCheckpointVelsEndNew[zGroup][client][i][0], g_iCheckpointVelsEndNew[zGroup][client][i][1], g_iCheckpointVelsEndNew[zGroup][client][i][2], 0, 0, 0, zGroup);
			tTransaction.AddQuery(szQuery);
		}
		g_dDb.Execute(tTransaction, SQLTxn_UpdateCheckpointsSuccess, SQLTxn_UpdateCheckpointsFailed, pack);
	}
}

public void SQLTxn_UpdateCheckpointsSuccess(Handle db, DataPack pack, int numQueries, Handle[] results, any[] queryData)
{
	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int zonegrp = ReadPackCell(pack);
	delete pack;

	if (IsValidClient(client))
	{
		db_viewCheckpointsinZoneGroup(client, g_szSteamID[client], g_szMapName, zonegrp);
	}
}

public void SQLTxn_UpdateCheckpointsFailed(Handle db, DataPack pack, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	delete pack;
	
	if (IsValidClient(client))
		CPrintToChat(client, "%t", "SQL10", g_szChatPrefix, error);
	PrintToServer("[Surftimer] Zone Removal Failed. Error: %s", error);
	LogError("[SurfTimer] Error updating checkpoints: %s", error);
}

/*===================================
=              MAPTIER              =
===================================*/

public void db_insertMapTier(int tier)
{
	char szQuery[256];
	if (g_bTierEntryFound)
	{
		Format(szQuery, sizeof(szQuery), sql_updatemaptier, tier, g_szMapName);
		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "db_insertMapTier - szQuery: %s", szQuery);
		}
		g_dDb.Query(db_insertMapTierCallback, szQuery, _, DBPrio_Low);
	}
	else
	{
		Format(szQuery, sizeof(szQuery), sql_insertmaptier, g_szMapName, tier);
		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "db_insertMapTier - szQuery: %s", szQuery);
		}
		g_dDb.Query(db_insertMapTierCallback, szQuery, _, DBPrio_Low);
	}
}

public void db_insertMapTierCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_insertMapTierCallback): %s", error);
		return;
	}

	db_selectMapTier();
}

public void db_selectMapTier()
{
	g_bTierEntryFound = false;

	char szQuery[1024];
	Format(szQuery, sizeof(szQuery), sql_selectMapTier, g_szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectMapTier - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_selectMapTierCallback, szQuery, _, DBPrio_Low);
}

public void SQL_selectMapTierCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_selectMapTierCallback): %s", error);
		if (!g_bServerDataLoaded)
			db_viewRecordCheckpointInMap();
		return;
	}
	g_bRankedMap = false;

	if (results.HasResults && results.FetchRow())
	{
		g_bTierEntryFound = true;
		int tier;

		// Format tier string
		tier = results.FetchInt(0);
		g_bRankedMap = view_as<bool>(results.FetchInt(1));
		if (0 < tier < 9)
		{
			g_bTierFound = true;
			g_iMapTier = tier;
			Format(g_sTierString, 512, "%c%s %c- ", BLUE, g_szMapName, WHITE);
			switch (tier)
			{
				case 1:Format(g_sTierString, 512, "%s%cTier %i %c- ", g_sTierString, GRAY, tier, WHITE);
				case 2:Format(g_sTierString, 512, "%s%cTier %i %c- ", g_sTierString, LIGHTBLUE, tier, WHITE);
				case 3:Format(g_sTierString, 512, "%s%cTier %i %c- ", g_sTierString, BLUE, tier, WHITE);
				case 4:Format(g_sTierString, 512, "%s%cTier %i %c- ", g_sTierString, DARKBLUE, tier, WHITE);
				case 5:Format(g_sTierString, 512, "%s%cTier %i %c- ", g_sTierString, RED, tier, WHITE);
				case 6:Format(g_sTierString, 512, "%s%cTier %i %c- ", g_sTierString, DARKRED, tier, WHITE);
				case 7:Format(g_sTierString, 512, "%s%cTier %i %c- ", g_sTierString, ORCHID, tier, WHITE);
				case 8:Format(g_sTierString, 512, "%s%cTier %i %c- ", g_sTierString, PURPLE, tier, WHITE);
				default:Format(g_sTierString, 512, "%s%cTier %i %c- ", g_sTierString, GRAY, tier, WHITE);
			}
			if (g_bhasStages)
				Format(g_sTierString, 512, "%s%c%i Stages", g_sTierString, LIGHTGREEN, (g_mapZonesTypeCount[0][3] + 1));
			else
				Format(g_sTierString, 512, "%s%cLinear", g_sTierString, LIMEGREEN);

			if (g_bhasBonus)
				if (g_mapZoneGroupCount > 2)
					Format(g_sTierString, 512, "%s %c-%c %i Bonuses", g_sTierString, WHITE, ORANGE, (g_mapZoneGroupCount - 1));
				else
					Format(g_sTierString, 512, "%s %c-%c Bonus", g_sTierString, WHITE, ORANGE, (g_mapZoneGroupCount - 1));
		}
	}
	else
	g_bTierEntryFound = false;

	if (!g_bServerDataLoaded)
		db_viewRecordCheckpointInMap();

	return;
}

/*===================================
=             SQL Bonus             =
===================================*/

public void db_currentBonusRunRank(int client, int zGroup)
{
	char szQuery[512];
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, zGroup);
	Format(szQuery, sizeof(szQuery), "SELECT count(runtime)+1 FROM ck_bonus WHERE mapname = '%s' AND zonegroup = '%i' AND runtime < %f", g_szMapName, zGroup, g_fFinalTime[client]);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_currentBonusRunRank - szQuery: %s", szQuery);
	}
	g_dDb.Query(db_viewBonusRunRank, szQuery, pack, DBPrio_Low);
}

public void db_viewBonusRunRank(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_viewBonusRunRank): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int zGroup = ReadPackCell(pack);
	delete pack;

	if (IsValidClient(client))
	{
		int rank;
		if (results.HasResults && results.FetchRow())
		{
			rank = results.FetchInt(0);
		}

		PrintChatBonus(client, zGroup, rank);
	}
}

public void db_viewMapRankBonus(int client, int zgroup, int type)
{
	char szQuery[1024];
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, zgroup);
	WritePackCell(pack, type);

	Format(szQuery, sizeof(szQuery), sql_selectPlayerRankBonus, g_szSteamID[client], g_szMapName, zgroup, g_szMapName, zgroup);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewMapRankBonus - szQuery: %s", szQuery);
	}
	g_dDb.Query(db_viewMapRankBonusCallback, szQuery, pack, DBPrio_Low);
}

public void db_viewMapRankBonusCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_viewMapRankBonusCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int zgroup = ReadPackCell(pack);
	int type = ReadPackCell(pack);
	delete pack;

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			g_MapRankBonus[zgroup][client] = results.RowCount;
		}
		else
		{
			g_MapRankBonus[zgroup][client] = 9999999;
		}

		switch (type)
		{
			case 1: {
				g_iBonusCount[zgroup]++;
				PrintChatBonus(client, zgroup);
			}
			case 2: {
				PrintChatBonus(client, zgroup);
			}
		}
	}
}

// Get player rank in bonus - current map
public void db_viewPersonalBonusRecords(int client, char szSteamId[32])
{
	char szQuery[1024];
	// "SELECT runtime, zonegroup, style FROM ck_bonus WHERE steamid = '%s AND mapname = '%s' AND runtime > '0.0'";
	Format(szQuery, sizeof(szQuery), sql_selectPersonalBonusRecords, szSteamId, g_szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewPersonalBonusRecords - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_selectPersonalBonusRecordsCallback, szQuery, GetClientUserId(client), DBPrio_Low);
}

public void SQL_selectPersonalBonusRecordsCallback(Database db, DBResultSet results, const char[] error, any userid)
{
	int client = GetClientOfUserId(userid);
	
	if (IsValidClient(client))
	{
		if (!IsValidDatabase(db, error))
		{
			if (StrContains(error, "Unknown column", false) != -1)
			{
				LogError("[Surftimer] (SQL_selectPersonalBonusRecordsCallback) Your database are not up to date! Please use the command \"sm_surftimer_upgrade\" to upgrade your database.");
			}
			else
			{
				LogError("[Surftimer] SQL Error (SQL_selectPersonalBonusRecordsCallback): %s", error);
			}

			if (!g_bSettingsLoaded[client])
				LoadClientSetting(client, g_iSettingToLoad[client]);
			return;
		}

		int zgroup;
		int style;

		for (int i = 0; i < MAXZONEGROUPS; i++)
		{
			g_fPersonalRecordBonus[i][client] = 0.0;
			Format(g_szPersonalRecordBonus[i][client], 64, "N/A");

			for (int j = 0; j < 3; j++)
			{
				int k;
				if (i == 0)
					k = i + 1;
				else
					k = i;

				g_iStartVelsRecord[client][k][j] = 0;
				g_iEndVelsRecord[client][k][j] = 0;
			}

			for (int s = 1; s < MAX_STYLES; s++)
			{
				g_fStylePersonalRecordBonus[s][i][client] = 0.0;
				Format(g_szStylePersonalRecordBonus[s][i][client], 64, "N/A");
			}
		}

		if (results.HasResults)
		{
			while (results.FetchRow())
			{
				zgroup = results.FetchInt(1);
				style = results.FetchInt(2);

				if (style == 0)
				{
					g_fPersonalRecordBonus[zgroup][client] = results.FetchFloat(0);

					g_iStartVelsRecord[client][zgroup][0] = results.FetchInt(3);
					g_iStartVelsRecord[client][zgroup][1] = results.FetchInt(4);
					g_iStartVelsRecord[client][zgroup][2] = results.FetchInt(5);
					g_iEndVelsRecord[client][zgroup][0] = results.FetchInt(6);
					g_iEndVelsRecord[client][zgroup][1] = results.FetchInt(7);
					g_iEndVelsRecord[client][zgroup][2] = results.FetchInt(8);

					if (g_fPersonalRecordBonus[zgroup][client] > 0.0)
					{
						FormatTimeFloat(client, g_fPersonalRecordBonus[zgroup][client], 3, g_szPersonalRecordBonus[zgroup][client], 64);
						db_viewMapRankBonus(client, zgroup, 0); // get rank
					}
					else
					{
						Format(g_szPersonalRecordBonus[zgroup][client], 64, "N/A");
						g_fPersonalRecordBonus[zgroup][client] = 0.0;
					}
				}
				else
				{
					g_fStylePersonalRecordBonus[style][zgroup][client] = results.FetchFloat(0);

					if (g_fStylePersonalRecordBonus[style][zgroup][client] > 0.0)
					{
						FormatTimeFloat(client, g_fStylePersonalRecordBonus[style][zgroup][client], 3, g_szStylePersonalRecordBonus[style][zgroup][client], 64);
						db_viewMapRankBonusStyle(client, zgroup, 0, style);
					}
					else
					{
						Format(g_szPersonalRecordBonus[zgroup][client], 64, "N/A");
						g_fPersonalRecordBonus[zgroup][client] = 0.0;
					}
				}
			}
		}

		if (!g_bSettingsLoaded[client])
		{
			g_fTick[client][1] = GetGameTime();
			float tick = g_fTick[client][1] - g_fTick[client][0];
			LogToFileEx(g_szLogFile, "[Surftimer] %s: Finished db_viewPersonalBonusRecords in %fs", g_szSteamID[client], tick);
			g_fTick[client][0] = GetGameTime();

			LoadClientSetting(client, g_iSettingToLoad[client]);
		}
		return;
	}
}

public void db_viewFastestBonus()
{
	char szQuery[1024];
	// SELECT name, MIN(runtime), zonegroup, style FROM ck_bonus WHERE mapname = '%s' GROUP BY zonegroup, style;
	Format(szQuery, sizeof(szQuery), sql_selectFastestBonus, g_szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewFastestBonus - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_selectFastestBonusCallback, szQuery, _, DBPrio_High);
}

public void SQL_selectFastestBonusCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		if (StrContains(error, "Unknown column", false) != -1)
		{
			LogError("[Surftimer] (SQL_selectFastestBonusCallback) Your database are not up to date! Please use the command \"sm_surftimer_upgrade\" to upgrade your database.");
		}
		else
		{
			LogError("[Surftimer] SQL Error (SQL_selectFastestBonusCallback): %s", error);
		}

		if (!g_bServerDataLoaded)
		{
			db_viewBonusTotalCount();
		}
		return;
	}

	for (int i = 0; i < MAXZONEGROUPS; i++)
	{
		Format(g_szBonusFastestTime[i], 64, "N/A");
		g_fBonusFastest[i] = 9999999.0;

		for (int j = 0; j < 3; j++)
		{	
			int k;
			if (i == 0)
				k = i + 1;
			else
				k = i;

			g_iStartVelsServerRecord[k][j] = 0;
			g_iEndVelsServerRecord[k][j] = 0;
		}

		for (int s = 1; s < MAX_STYLES; s++)
		{
			Format(g_szStyleBonusFastestTime[s][i], 64, "N/A");
			g_fStyleBonusFastest[s][i] = 9999999.0;
		}
	}

	if (results.HasResults)
	{
		int zonegroup;
		int style;
		while (results.FetchRow())
		{
			zonegroup = results.FetchInt(2);
			style = results.FetchInt(3);

			if (style == 0)
			{
				results.FetchString(0, g_szBonusFastest[zonegroup], MAX_NAME_LENGTH);
				g_fBonusFastest[zonegroup] = results.FetchFloat(1);
				FormatTimeFloat(1, g_fBonusFastest[zonegroup], 3, g_szBonusFastestTime[zonegroup], 64);

				g_iStartVelsServerRecord[zonegroup][0] = results.FetchInt(4);
				g_iStartVelsServerRecord[zonegroup][1] = results.FetchInt(5);
				g_iStartVelsServerRecord[zonegroup][2] = results.FetchInt(6);
				g_iEndVelsServerRecord[zonegroup][0] = results.FetchInt(7);
				g_iEndVelsServerRecord[zonegroup][1] = results.FetchInt(8);
				g_iEndVelsServerRecord[zonegroup][2] = results.FetchInt(9);
			}
			else
			{
				results.FetchString(0, g_szStyleBonusFastest[style][zonegroup], MAX_NAME_LENGTH);
				g_fStyleBonusFastest[style][zonegroup] = results.FetchFloat(1);
				FormatTimeFloat(1, g_fStyleBonusFastest[style][zonegroup], 3, g_szStyleBonusFastestTime[style][zonegroup], 64);
			}
		}
	}

	for (int i = 0; i < MAXZONEGROUPS; i++)
	{
		if (g_fBonusFastest[i] == 0.0)
			g_fBonusFastest[i] = 9999999.0;

		for (int s = 1; s < MAX_STYLES; s++)
		{
			if (g_fStyleBonusFastest[s][i] == 0.0)
				g_fStyleBonusFastest[s][i] = 9999999.0;
		}
	}

	if (!g_bServerDataLoaded)
	{
		db_viewBonusTotalCount();
	}
	return;
}

public void db_viewBonusTotalCount()
{
	char szQuery[1024];
	// SELECT zonegroup, style, count(1) FROM ck_bonus WHERE mapname = '%s' GROUP BY zonegroup, style;
	Format(szQuery, sizeof(szQuery), sql_selectBonusCount, g_szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewBonusTotalCount - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_selectBonusTotalCountCallback, szQuery, _, DBPrio_Low);
}

public void SQL_selectBonusTotalCountCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_selectBonusTotalCountCallback): %s", error);
		if (!g_bServerDataLoaded)
			db_selectMapTier();
		return;
	}

	for (int i = 1; i < MAXZONEGROUPS; i++)
	g_iBonusCount[i] = 0;

	if (results.HasResults)
	{
		int zonegroup;
		int style;
		while (results.FetchRow())
		{
			zonegroup = results.FetchInt(0);
			style = results.FetchInt(1);
			if (style == 0)
				g_iBonusCount[zonegroup] = results.FetchInt(2);
			else
				g_iStyleBonusCount[style][zonegroup] = results.FetchInt(2);
		}
	}

	if (!g_bServerDataLoaded)
		db_selectMapTier();

	return;
}

public void db_insertBonus(int client, char szSteamId[32], char szUName[MAX_NAME_LENGTH], float FinalTime, int zoneGrp)
{
	char szQuery[1024];
	char szName[MAX_NAME_LENGTH * 2 + 1];
	g_dDb.Escape(szUName, szName, MAX_NAME_LENGTH * 2 + 1);
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, zoneGrp);
	Format(szQuery, sizeof(szQuery), sql_insertBonus, szSteamId, szName, g_szMapName, FinalTime, zoneGrp, g_iStartVelsNew[client][zoneGrp][0], g_iStartVelsNew[client][zoneGrp][1], g_iStartVelsNew[client][zoneGrp][2], g_iEndVelsNew[client][zoneGrp][0], g_iEndVelsNew[client][zoneGrp][1], g_iEndVelsNew[client][zoneGrp][2]);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_insertBonus - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_insertBonusCallback, szQuery, pack, DBPrio_Low);
}

public void SQL_insertBonusCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[Surftimer] SQL Error (SQL_insertBonusCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int zgroup = ReadPackCell(pack);
	delete pack;

	if (IsValidClient(client))
	{
		for (int i = 0; i < 3; i++)
		{
			g_iStartVelsRecord[client][zgroup][i] = g_iStartVelsNew[client][zgroup][i];
			g_iEndVelsRecord[client][zgroup][i] = g_iEndVelsNew[client][zgroup][i];
		}

		db_viewMapRankBonus(client, zgroup, 1);
		// Change to update profile timer, if giving multiplier count or extra points for bonuses
		CalculatePlayerRank(client, 0);
	}
}

public void db_updateBonus(int client, char szSteamId[32], char szUName[MAX_NAME_LENGTH], float FinalTime, int zoneGrp)
{
	char szQuery[1024];
	char szName[MAX_NAME_LENGTH * 2 + 1];
	Handle datapack = CreateDataPack();
	WritePackCell(datapack, GetClientUserId(client));
	WritePackCell(datapack, zoneGrp);

	g_dDb.Escape(szUName, szName, MAX_NAME_LENGTH * 2 + 1);
	Format(szQuery, sizeof(szQuery), sql_updateBonus, FinalTime, szName, g_iStartVelsNew[client][zoneGrp][0], g_iStartVelsNew[client][zoneGrp][1], g_iStartVelsNew[client][zoneGrp][2], g_iEndVelsNew[client][zoneGrp][0], g_iEndVelsNew[client][zoneGrp][1], g_iEndVelsNew[client][zoneGrp][2], szSteamId, g_szMapName, zoneGrp);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_updateBonus - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_updateBonusCallback, szQuery, datapack, DBPrio_Low);
}


public void SQL_updateBonusCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[Surftimer] SQL Error (SQL_updateBonusCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int zgroup = ReadPackCell(pack);
	delete pack;

	if (IsValidClient(client))
	{
		for (int i = 0; i < 3; i++)
		{
			g_iStartVelsRecord[client][zgroup][i] = g_iStartVelsNew[client][zgroup][i];
			g_iEndVelsRecord[client][zgroup][i] = g_iEndVelsNew[client][zgroup][i];
		}

		db_viewMapRankBonus(client, zgroup, 2);

		CalculatePlayerRank(client, 0);
	}
}

public void db_selectBonusCount()
{
	char szQuery[258];
	Format(szQuery, sizeof(szQuery), sql_selectTotalBonusCount);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectBonusCount - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_selectBonusCountCallback, szQuery, _, DBPrio_Low);
}

public void SQL_selectBonusCountCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_selectBonusCountCallback): %s", error);
		return;
	}

	if (results.HasResults)
	{
		char mapName[128];
		char mapName2[128];
		g_totalBonusCount = 0;
		while (results.FetchRow())
		{
			results.FetchString(0, mapName2, 128);
			for (int i = 0; i < GetArraySize(g_MapList); i++)
			{
				GetArrayString(g_MapList, i, mapName, 128);
				if (StrEqual(mapName, mapName2, false))
				g_totalBonusCount++;
			}
		}
	}
	else
	{
		g_totalBonusCount = 0;
	}
	SetSkillGroups();
}

/*===================================
=             SQL Zones             =
===================================*/

public void db_setZoneNames(int client, char szName[128])
{
	char szQuery[512], szEscapedName[128 * 2 + 1];
	g_dDb.Escape(szName, szEscapedName, 128 * 2 + 1);
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, g_CurrentSelectedZoneGroup[client]);
	WritePackString(pack, szEscapedName);
	// UPDATE ck_zones SET zonename = '%s' WHERE mapname = '%s' AND zonegroup = '%i';
	Format(szQuery, sizeof(szQuery), sql_setZoneNames, szEscapedName, g_szMapName, g_CurrentSelectedZoneGroup[client]);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_setZoneNames - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_setZoneNamesCallback, szQuery, pack, DBPrio_Low);
}

public void sql_setZoneNamesCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_setZoneNamesCallback): %s", error);
		delete pack;
		return;
	}

	char szName[64];
	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int zonegrp = ReadPackCell(pack);
	ReadPackString(pack, szName, 64);
	delete pack;

	if (IsValidClient(client))
	{
		for (int i = 0; i < g_mapZonesCount; i++)
		{
			if (g_mapZones[i].ZoneGroup == zonegrp)
			Format(g_mapZones[i].ZoneName, 64, szName);
		}

		if (IsValidClient(client))
		{
			CPrintToChat(client, "%t", "SQL4", g_szChatPrefix);
			ListBonusSettings(client);
		}
		db_selectMapZones();
	}
}

public void db_checkAndFixZoneIds()
{
	char szQuery[512];
	// "SELECT mapname, zoneid, zonetype, zonetypeid, pointa_x, pointa_y, pointa_z, pointb_x, pointb_y, pointb_z, vis, team, zonegroup, zonename FROM ck_zones WHERE mapname = '%s' ORDER BY zoneid ASC";
	if (!g_szMapName[0])
	GetCurrentMap(g_szMapName, 128);

	Format(szQuery, sizeof(szQuery), sql_selectZoneIds, g_szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_checkAndFixZoneIds - szQuery: %s", szQuery);
	}
	g_dDb.Query(db_checkAndFixZoneIdsCallback, szQuery, _, DBPrio_Low);
}

public void db_checkAndFixZoneIdsCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_checkAndFixZoneIdsCallback): %s", error);
		return;
	}

	if (results.HasResults)
	{
		bool IDError = false;
		float x1[128], y1[128], z1[128], x2[128], y2[128], z2[128];
		int checker = 0, i, zonetype[128], zonetypeid[128], vis[128], team[128], zoneGrp[128];
		char zName[128][128];
		char hookname[128][128], targetname[128][128];
		int onejumplimit[128];
		float prespeed[128];

		while (results.FetchRow())
		{
			i = results.FetchInt(1);
			zonetype[checker] = results.FetchInt(2);
			zonetypeid[checker] = results.FetchInt(3);
			x1[checker] = results.FetchFloat(4);
			y1[checker] = results.FetchFloat(5);
			z1[checker] = results.FetchFloat(6);
			x2[checker] = results.FetchFloat(7);
			y2[checker] = results.FetchFloat(8);
			z2[checker] = results.FetchFloat(9);
			vis[checker] = results.FetchInt(10);
			team[checker] = results.FetchInt(11);
			zoneGrp[checker] = results.FetchInt(12);
			results.FetchString(13, zName[checker], 128);
			results.FetchString(14, hookname[checker], 128);
			results.FetchString(15, targetname[checker], 128);
			onejumplimit[checker] = results.FetchInt(16);
			prespeed[checker] = results.FetchFloat(17);

			if (i != checker)
			IDError = true;

			checker++;
		}

		if (IDError)
		{
			char szQuery[256];
			Format(szQuery, sizeof(szQuery), sql_deleteMapZones, g_szMapName);
			if (g_cLogQueries.BoolValue)
			{
				LogToFile(g_szQueryFile, "db_checkAndFixZoneIdsCallback - szQuery: %s", szQuery);
			}
			g_dDb.Query(SQL_CheckCallback, szQuery, _, DBPrio_Low);
			// SQL_FastQuery(g_hDb, szQuery);

			for (int k = 0; k < checker; k++)
			{
				db_insertZoneCheap(k, zonetype[k], zonetypeid[k], x1[k], y1[k], z1[k], x2[k], y2[k], z2[k], vis[k], team[k], zoneGrp[k], zName[k], -10, hookname[k], targetname[k], onejumplimit[k], prespeed[k]);
			}
		}
	}
	db_selectMapZones();
}

public void ZoneDefaultName(int zonetype, int zonegroup, char zName[128])
{
	if (zonegroup > 0)
		Format(zName, 64, "bonus %i", zonegroup);
	else
	if (-1 < zonetype < ZONEAMOUNT)
	Format(zName, 128, "%s %i", g_szZoneDefaultNames[zonetype], zonegroup);
	else
	Format(zName, 64, "Unknown");
}

public void db_insertZoneCheap(int zoneid, int zonetype, int zonetypeid, float pointax, float pointay, float pointaz, float pointbx, float pointby, float pointbz, int vis, int team, int zGrp, char zName[128], int query, char hookname[128], char targetname[128], int ojl, float prespeed)
{
	char szQuery[1024];
	// "INSERT INTO ck_zones (mapname, zoneid, zonetype, zonetypeid, pointa_x, pointa_y, pointa_z, pointb_x, pointb_y, pointb_z, vis, team, zonegroup, zonename) VALUES ('%s', '%i', '%i', '%i', '%f', '%f', '%f', '%f', '%f', '%f', '%i', '%i', '%i', '%s')";
	Format(szQuery, sizeof(szQuery), sql_insertZones, g_szMapName, zoneid, zonetype, zonetypeid, pointax, pointay, pointaz, pointbx, pointby, pointbz, vis, team, zGrp, zName, hookname, targetname, ojl, prespeed);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_insertZoneCheap - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_insertZonesCheapCallback, szQuery, query, DBPrio_Low);
}

public void SQL_insertZonesCheapCallback(Database db, DBResultSet results, const char[] error, any query)
{
	if (!IsValidDatabase(db, error))
	{
		CPrintToChatAll("%t", "SQL5", g_szChatPrefix);
		db_checkAndFixZoneIds();
		return;
	}
	if (query == (g_mapZonesCount - 1))
	db_selectMapZones();
}

public void db_insertZone(int zoneid, int zonetype, int zonetypeid, float pointax, float pointay, float pointaz, float pointbx, float pointby, float pointbz, int vis, int team, int zonegroup)
{
	char szQuery[1024];
	char zName[128];

	if (zonegroup == g_mapZoneGroupCount)
	ZoneDefaultName(zonetype, zonegroup, zName);
	else
	Format(zName, 128, g_szZoneGroupName[zonegroup]);

	// char sql_insertZones[] = "INSERT INTO ck_zones (mapname, zoneid, zonetype, zonetypeid, pointa_x, pointa_y, pointa_z, pointb_x, pointb_y, pointb_z, vis, team, zonegroup, zonename, hookname, targetname, onejumplimit, prespeed) VALUES ('%s', '%i', '%i', '%i', '%f', '%f', '%f', '%f', '%f', '%f', '%i', '%i', '%i','%s','%s','%s',%i,%f)";
	Format(szQuery, sizeof(szQuery), sql_insertZones, g_szMapName, zoneid, zonetype, zonetypeid, pointax, pointay, pointaz, pointbx, pointby, pointbz, vis, team, zonegroup, zName, "None", "player", 1, 250.0);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_insertZone - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_insertZonesCallback, szQuery, _, DBPrio_Low);
}

public void SQL_insertZonesCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		CPrintToChatAll("%t", "SQL5", g_szChatPrefix);
		db_checkAndFixZoneIds();
		return;
	}

	db_selectMapZones();
}

public void db_insertZoneHook(int zoneid, int zonetype, int zonetypeid, int vis, int team, int zonegroup, char[] szHookName, float point_a[3], float point_b[3])
{
	char szQuery[1024];
	char zName[128];

	if (zonegroup == g_mapZoneGroupCount)
	ZoneDefaultName(zonetype, zonegroup, zName);
	else
	Format(zName, 128, g_szZoneGroupName[zonegroup]);

	// "INSERT INTO ck_zones (mapname, zoneid, zonetype, zonetypeid, pointa_x, pointa_y, pointa_z, pointb_x, pointb_y, pointb_z, vis, team, zonegroup, zonename) VALUES ('%s', '%i', '%i', '%i', '%f', '%f', '%f', '%f', '%f', '%f', '%i', '%i', '%i', '%s')";
	Format(szQuery, sizeof(szQuery), "INSERT INTO ck_zones (mapname, zoneid, zonetype, zonetypeid, pointa_x, pointa_y, pointa_z, pointb_x, pointb_y, pointb_z, vis, team, zonegroup, zonename, hookname) VALUES ('%s', '%i', '%i', '%i', '%f', '%f', '%f', '%f', '%f', '%f', '%i', '%i', '%i','%s','%s')", g_szMapName, zoneid, zonetype, zonetypeid, point_a[0], point_a[1], point_a[2], point_b[0], point_b[1], point_b[2], vis, team, zonegroup, zName, szHookName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_insertZoneHook - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_insertZonesCallback, szQuery, _, DBPrio_Low);
}

public void db_saveZones()
{
	char szQuery[258];
	Format(szQuery, sizeof(szQuery), sql_deleteMapZones, g_szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_saveZones - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_saveZonesCallBack, szQuery, _, DBPrio_Low);
}

public void SQL_saveZonesCallBack(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_saveZonesCallBack): %s", error);
		return;
	}
	char szzone[128];
	char hookname[128], targetname[128];
	for (int i = 0; i < g_mapZonesCount; i++)
	{
		Format(szzone, 128, "%s", g_szZoneGroupName[g_mapZones[i].ZoneGroup]);
		Format(hookname, 128, "%s", g_mapZones[i].HookName);
		Format(targetname, 128, "%s", g_mapZones[i].TargetName);

		if (g_mapZones[i].PointA[0] != -1.0 && g_mapZones[i].PointA[1] != -1.0 && g_mapZones[i].PointA[2] != -1.0)
		{
			db_insertZoneCheap(g_mapZones[i].ZoneId, g_mapZones[i].ZoneType, g_mapZones[i].ZoneTypeId, g_mapZones[i].PointA[0], g_mapZones[i].PointA[1], g_mapZones[i].PointA[2], g_mapZones[i].PointB[0], g_mapZones[i].PointB[1], g_mapZones[i].PointB[2], g_mapZones[i].Vis, g_mapZones[i].Team, g_mapZones[i].ZoneGroup, szzone, i, hookname, targetname, g_mapZones[i].OneJumpLimit, g_mapZones[i].PreSpeed);
		}
	}
}

public void db_updateZone(int zoneid, int zonetype, int zonetypeid, float[] Point1, float[] Point2, int vis, int team, int zonegroup, int onejumplimit, float prespeed, char[] hookname, char[] targetname)
{
	char szQuery[1024];
	Format(szQuery, sizeof(szQuery), sql_updateZone, zonetype, zonetypeid, Point1[0], Point1[1], Point1[2], Point2[0], Point2[1], Point2[2], vis, team, onejumplimit, prespeed, hookname, targetname, zonegroup, zoneid, g_szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_updateZone - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_updateZoneCallback, szQuery, _, DBPrio_Low);
}

public void SQL_updateZoneCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_updateZoneCallback): %s", error);
		return;
	}

	db_selectMapZones();
}

public int db_deleteZonesInGroup(int client)
{
	char szQuery[258];

	if (g_CurrentSelectedZoneGroup[client] < 1)
	{
		if (IsValidClient(client))
		CPrintToChat(client, "%t", "SQL6", g_szChatPrefix, g_CurrentSelectedZoneGroup[client]);

		PrintToServer("surftimer | Invalid zonegroup index selected, aborting. (%i)", g_CurrentSelectedZoneGroup[client]);
	}

	Transaction tTransaction = new Transaction();

	Format(szQuery, sizeof(szQuery), sql_deleteZonesInGroup, g_szMapName, g_CurrentSelectedZoneGroup[client]);
	tTransaction.AddQuery(szQuery);

	Format(szQuery, sizeof(szQuery), "DELETE FROM ck_bonus WHERE zonegroup = %i AND mapname = '%s';", g_CurrentSelectedZoneGroup[client], g_szMapName);
	tTransaction.AddQuery(szQuery);

	g_dDb.Execute(tTransaction, SQLTxn_ZoneGroupRemovalSuccess, SQLTxn_ZoneGroupRemovalFailed, GetClientUserId(client));
}

public void SQLTxn_ZoneGroupRemovalSuccess(Database db, int userid, int numQueries, DBResultSet[] results, any[] queryData)
{
	PrintToServer("surftimer | Zonegroup removal was successful");

	db_selectMapZones();
	db_viewFastestBonus();
	db_viewBonusTotalCount();
	db_viewRecordCheckpointInMap();

	int client = GetClientOfUserId(userid);
	if (IsValidClient(client))
	{
		ZoneMenu(client);
		CPrintToChat(client, "%t", "SQL7", g_szChatPrefix);
	}
	return;
}

public void SQLTxn_ZoneGroupRemovalFailed(Database db, int userid, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	int client = GetClientOfUserId(userid);
	if (IsValidClient(client))
	{
		CPrintToChat(client, "%t", "SQL8", g_szChatPrefix, error);
	}

	PrintToServer("surftimer | Zonegroup removal failed (Error: %s)", error);
	return;
}

public void db_selectzoneTypeIds(int zonetype, int client, int zonegrp)
{
	char szQuery[258];
	Format(szQuery, sizeof(szQuery), sql_selectzoneTypeIds, g_szMapName, zonetype, zonegrp);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectzoneTypeIds - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_selectzoneTypeIdsCallback, szQuery, GetClientUserId(client), DBPrio_Low);
}

public void SQL_selectzoneTypeIdsCallback(Database db, DBResultSet results, const char[] error, int userid)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_selectzoneTypeIdsCallback): %s", error);
		return;
	}

	if (results.HasResults)
	{
		int availableids[MAXZONES] = { 0, ... }, i;
		while (results.FetchRow())
		{
			i = results.FetchInt(0);
			if (i < MAXZONES)
			availableids[i] = 1;
		}
		Menu TypeMenu = new Menu(Handle_EditZoneTypeId);
		char MenuNum[24], MenuInfo[6], MenuItemName[24];
		int x = 0;
		// Types: Start(1), End(2), Stage(3), Checkpoint(4), Speed(5), TeleToStart(6), Validator(7), Chekcer(8), Stop(0) //fluffys AntiJump(9), AntiDuck(10)

		int client = GetClientOfUserId(userid);

		if (IsValidClient(client))
		{
			switch (g_CurrentZoneType[client]) {
				case 0:Format(MenuItemName, 24, "Stop");
				case 1:Format(MenuItemName, 24, "Start");
				case 2:Format(MenuItemName, 24, "End");
				case 3: {
					Format(MenuItemName, 24, "Stage");
					x = 2;
				}
				case 4:Format(MenuItemName, 24, "Checkpoint");
				case 5:Format(MenuItemName, 24, "Speed");
				case 6:Format(MenuItemName, 24, "TeleToStart");
				case 7:Format(MenuItemName, 24, "Validator");
				case 8:Format(MenuItemName, 24, "Checker");
				// fluffys
				case 9:Format(MenuItemName, 24, "AntiJump");
				case 10:Format(MenuItemName, 24, "AntiDuck");
				case 11:Format(MenuItemName, 24, "MaxSpeed");
				default:Format(MenuItemName, 24, "Unknown");
			}

			for (int k = 0; k < 35; k++)
			{
				if (availableids[k] == 0)
				{
					Format(MenuNum, sizeof(MenuNum), "%s-%i", MenuItemName, (k + x));
					Format(MenuInfo, sizeof(MenuInfo), "%i", k);
					TypeMenu.AddItem(MenuInfo, MenuNum);
				}
			}
			TypeMenu.ExitButton = true;
			TypeMenu.Display(client, MENU_TIME_FOREVER);
		}
	}
}

public void db_selectMapZones()
{
	char szQuery[512];
	Format(szQuery, sizeof(szQuery), sql_selectMapZones, g_szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectMapZones - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_selectMapZonesCallback, szQuery, _, DBPrio_High);
}

public void SQL_selectMapZonesCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_selectMapZonesCallback): %s", error);
		if (!g_bServerDataLoaded)
		{
			db_GetMapRecord_Pro();
		}
		return;
	}

	RemoveZones();

	if (results.HasResults)
	{
		g_mapZonesCount = 0;
		g_bhasStages = false;
		g_bhasBonus = false;
		g_mapZoneGroupCount = 0; // 1 = No Bonus, 2 = Bonus, >2 = Multiple bonuses
		g_iTotalCheckpoints = 0;

		for (int i = 0; i < MAXZONES; i++)
		{
			g_mapZones[i].ZoneId = -1;
			g_mapZones[i].PointA = view_as<float>({ -1.0, -1.0, -1.0 });
			g_mapZones[i].PointB = view_as<float>({ -1.0, -1.0, -1.0 });
			g_mapZones[i].ZoneId = -1;
			g_mapZones[i].ZoneType = -1;
			g_mapZones[i].ZoneTypeId = -1;
			Format(g_mapZones[i].ZoneName, sizeof(MapZone::ZoneName), "");
			Format(g_mapZones[i].HookName, sizeof(MapZone::HookName), "");
			g_mapZones[i].Vis = 0;
			g_mapZones[i].Team = 0;
			g_mapZones[i].ZoneGroup = 0;
			Format(g_mapZones[i].TargetName, sizeof(MapZone::TargetName), "");
			g_mapZones[i].OneJumpLimit = 1;
			g_mapZones[i].PreSpeed = 350.0;
		}

		for (int x = 0; x < MAXZONEGROUPS; x++)
		{
			g_mapZoneCountinGroup[x] = 0;
			for (int k = 0; k < ZONEAMOUNT; k++)
			g_mapZonesTypeCount[x][k] = 0;
		}

		int zoneIdChecker[MAXZONES], zoneTypeIdChecker[MAXZONEGROUPS][ZONEAMOUNT][MAXZONES], zoneTypeIdCheckerCount[MAXZONEGROUPS][ZONEAMOUNT], zoneGroupChecker[MAXZONEGROUPS];

		// Types: Start(1), End(2), Stage(3), Checkpoint(4), Speed(5), TeleToStart(6), Validator(7), Chekcer(8), Stop(0)
		while (results.FetchRow())
		{
			g_mapZones[g_mapZonesCount].ZoneId = results.FetchInt(0);
			g_mapZones[g_mapZonesCount].ZoneType = results.FetchInt(1);
			g_mapZones[g_mapZonesCount].ZoneTypeId = results.FetchInt(2);
			g_mapZones[g_mapZonesCount].PointA[0] = results.FetchFloat(3);
			g_mapZones[g_mapZonesCount].PointA[1] = results.FetchFloat(4);
			g_mapZones[g_mapZonesCount].PointA[2] = results.FetchFloat(5);
			g_mapZones[g_mapZonesCount].PointB[0] = results.FetchFloat(6);
			g_mapZones[g_mapZonesCount].PointB[1] = results.FetchFloat(7);
			g_mapZones[g_mapZonesCount].PointB[2] = results.FetchFloat(8);
			g_mapZones[g_mapZonesCount].Vis = results.FetchInt(9);
			g_mapZones[g_mapZonesCount].Team = results.FetchInt(10);
			g_mapZones[g_mapZonesCount].ZoneGroup = results.FetchInt(11);

			// Total amount of checkpoints
			if (g_mapZones[g_mapZonesCount].ZoneType == 4)
				g_iTotalCheckpoints++;

			/**
			* Initialize error checking
			* 0 = zone not found
			* 1 = zone found
			*
			* IDs must be in order 0, 1, 2....
			* Duplicate zoneids not possible due to primary key
			*/
			zoneIdChecker[g_mapZones[g_mapZonesCount].ZoneId]++;
			if (zoneGroupChecker[g_mapZones[g_mapZonesCount].ZoneGroup] != 1)
			{
				// 1 = No Bonus, 2 = Bonus, >2 = Multiple bonuses
				g_mapZoneGroupCount++;
				zoneGroupChecker[g_mapZones[g_mapZonesCount].ZoneGroup] = 1;
			}

			// You can have the same zonetype and zonetypeid values in different zonegroups
			zoneTypeIdChecker[g_mapZones[g_mapZonesCount].ZoneGroup][g_mapZones[g_mapZonesCount].ZoneType][g_mapZones[g_mapZonesCount].ZoneTypeId]++;
			zoneTypeIdCheckerCount[g_mapZones[g_mapZonesCount].ZoneGroup][g_mapZones[g_mapZonesCount].ZoneType]++;

			results.FetchString(12, g_mapZones[g_mapZonesCount].ZoneName, sizeof(MapZone::ZoneName));
			results.FetchString(13, g_mapZones[g_mapZonesCount].HookName, sizeof(MapZone::HookName));
			results.FetchString(14, g_mapZones[g_mapZonesCount].TargetName, sizeof(MapZone::TargetName));
			g_mapZones[g_mapZonesCount].OneJumpLimit = results.FetchInt(15);
			g_mapZones[g_mapZonesCount].PreSpeed = results.FetchFloat(16);

			if (!g_mapZones[g_mapZonesCount].ZoneName[0])
			{
				switch (g_mapZones[g_mapZonesCount].ZoneType)
				{
					case 0: {
						Format(g_mapZones[g_mapZonesCount].ZoneName, sizeof(MapZone::ZoneName), "Stop-%i", g_mapZones[g_mapZonesCount].ZoneTypeId);
					}
					case 1: {
						if (g_mapZones[g_mapZonesCount].ZoneGroup > 0)
						{
							g_bhasBonus = true;
							Format(g_mapZones[g_mapZonesCount].ZoneName, sizeof(MapZone::ZoneName), "BonusStart-%i", g_mapZones[g_mapZonesCount].ZoneTypeId);
							Format(g_szZoneGroupName[g_mapZones[g_mapZonesCount].ZoneGroup], sizeof(MapZone::ZoneGroup), "Bonus %i", g_mapZones[g_mapZonesCount].ZoneGroup);
						}
						else
						Format(g_mapZones[g_mapZonesCount].ZoneName, sizeof(MapZone::ZoneName), "Start-%i", g_mapZones[g_mapZonesCount].ZoneTypeId);
					}
					case 2: {
						if (g_mapZones[g_mapZonesCount].ZoneGroup > 0)
						Format(g_mapZones[g_mapZonesCount].ZoneName, sizeof(MapZone::ZoneName), "BonusEnd-%i", g_mapZones[g_mapZonesCount].ZoneTypeId);
						else
						Format(g_mapZones[g_mapZonesCount].ZoneName, sizeof(MapZone::ZoneName), "End-%i", g_mapZones[g_mapZonesCount].ZoneTypeId);
					}
					case 3: {
						g_bhasStages = true;
						Format(g_mapZones[g_mapZonesCount].ZoneName, sizeof(MapZone::ZoneName), "Stage-%i", (g_mapZones[g_mapZonesCount].ZoneTypeId + 2));
					}
					case 4: {
						Format(g_mapZones[g_mapZonesCount].ZoneName, sizeof(MapZone::ZoneName), "Checkpoint-%i", g_mapZones[g_mapZonesCount].ZoneTypeId);
					}
					case 5: {
						Format(g_mapZones[g_mapZonesCount].ZoneName, sizeof(MapZone::ZoneName), "Speed-%i", g_mapZones[g_mapZonesCount].ZoneTypeId);
					}
					case 6: {
						Format(g_mapZones[g_mapZonesCount].ZoneName, sizeof(MapZone::ZoneName), "TeleToStart-%i", g_mapZones[g_mapZonesCount].ZoneTypeId);
					}
					case 7: {
						Format(g_mapZones[g_mapZonesCount].ZoneName, sizeof(MapZone::ZoneName), "Validator-%i", g_mapZones[g_mapZonesCount].ZoneTypeId);
					}
					case 8: {
						Format(g_mapZones[g_mapZonesCount].ZoneName, sizeof(MapZone::ZoneName), "Checker-%i", g_mapZones[g_mapZonesCount].ZoneTypeId);
					}
					case 9: { // fluffys
						Format(g_mapZones[g_mapZonesCount].ZoneName, sizeof(MapZone::ZoneName), "AntiJump-%i", g_mapZones[g_mapZonesCount].ZoneTypeId);
					}
					case 10: {
						Format(g_mapZones[g_mapZonesCount].ZoneName, sizeof(MapZone::ZoneName), "AntiDuck-%i", g_mapZones[g_mapZonesCount].ZoneTypeId);
					}
					case 11: {
						Format(g_mapZones[g_mapZonesCount].ZoneName, sizeof(MapZone::ZoneName), "MaxSpeed-%i", g_mapZones[g_mapZonesCount].ZoneTypeId);
					}
				}
			}
			else
			{
				switch (g_mapZones[g_mapZonesCount].ZoneType)
				{
					case 1:
					{
						if (g_mapZones[g_mapZonesCount].ZoneGroup > 0)
							g_bhasBonus = true;
						Format(g_szZoneGroupName[g_mapZones[g_mapZonesCount].ZoneGroup], 128, "%s", g_mapZones[g_mapZonesCount].ZoneName);
					}
					case 3: g_bhasStages = true;
				}
			}

			/**
			*	Count zone center
			**/
			// Center
			float posA[3], posB[3], result[3];
			Array_Copy(g_mapZones[g_mapZonesCount].PointA, posA, 3);
			Array_Copy(g_mapZones[g_mapZonesCount].PointB, posB, 3);
			AddVectors(posA, posB, result);
			g_mapZones[g_mapZonesCount].CenterPoint[0] = result[0] / 2.0;
			g_mapZones[g_mapZonesCount].CenterPoint[1] = result[1] / 2.0;
			g_mapZones[g_mapZonesCount].CenterPoint[2] = result[2] / 2.0;

			for (int i = 0; i < 3; i++)
			{
				g_fZoneCorners[g_mapZonesCount][0][i] = g_mapZones[g_mapZonesCount].PointA[i];
				g_fZoneCorners[g_mapZonesCount][7][i] = g_mapZones[g_mapZonesCount].PointB[i];
			}

			// Zone counts:
			g_mapZonesTypeCount[g_mapZones[g_mapZonesCount].ZoneGroup][g_mapZones[g_mapZonesCount].ZoneType]++;
			g_mapZonesCount++;
		}
		// Count zone corners
		// https://forums.alliedmods.net/showpost.php?p=2006539&postcount=8
		for (int x = 0; x < g_mapZonesCount; x++)
		{
			for(int i = 1; i < 7; i++)
			{
				for(int j = 0; j < 3; j++)
				{
					g_fZoneCorners[x][i][j] = g_fZoneCorners[x][((i >> (2-j)) & 1) * 7][j];
				}
			}
		}

		/**
		* Check for errors
		*
		* 1. ZoneId
		*/
		char szQuery[258];
		for (int i = 0; i < g_mapZonesCount; i++)
		if (zoneIdChecker[i] == 0)
		{
			PrintToServer("[SurfTimer] Found an error in zoneid : %i", i);
			Format(szQuery, sizeof(szQuery), "UPDATE `ck_zones` SET zoneid = zoneid-1 WHERE mapname = '%s' AND zoneid > %i", g_szMapName, i);
			PrintToServer("Query: %s", szQuery);
			if (g_cLogQueries.BoolValue)
			{
				LogToFile(g_szQueryFile, "SQL_selectMapZonesCallback - szQuery: %s", szQuery);
			}
			g_dDb.Query(sql_zoneFixCallback, szQuery, _, DBPrio_Low);
			return;
		}

		// 2nd ZoneGroup
		for (int i = 0; i < g_mapZoneGroupCount; i++)
		if (zoneGroupChecker[i] == 0)
		{
			PrintToServer("[SurfTimer] Found an error in zonegroup %i (ZoneGroups total: %i)", i, g_mapZoneGroupCount);
			Format(szQuery, sizeof(szQuery), "UPDATE `ck_zones` SET `zonegroup` = zonegroup-1 WHERE `mapname` = '%s' AND `zonegroup` > %i", g_szMapName, i);
			if (g_cLogQueries.BoolValue)
			{
				LogToFile(g_szQueryFile, "SQL_selectMapZonesCallback - szQuery: %s", szQuery);
			}
			g_dDb.Query(sql_zoneFixCallback, szQuery, zoneGroupChecker[i], DBPrio_Low);
			return;
		}

		// 3rd ZoneTypeId
		for (int i = 0; i < g_mapZoneGroupCount; i++)
		for (int k = 0; k < ZONEAMOUNT; k++)
		for (int x = 0; x < zoneTypeIdCheckerCount[i][k]; x++)
		if (zoneTypeIdChecker[i][k][x] != 1 && (k == 3) || (k == 4))
		{
			if (zoneTypeIdChecker[i][k][x] == 0)
			{
				PrintToServer("[SurfTimer] ZoneTypeID missing! [ZoneGroup: %i ZoneType: %i, ZonetypeId: %i]", i, k, x);
				Format(szQuery, sizeof(szQuery), "UPDATE `ck_zones` SET zonetypeid = zonetypeid-1 WHERE mapname = '%s' AND zonetype = %i AND zonetypeid > %i AND zonegroup = %i;", g_szMapName, k, x, i);
				if (g_cLogQueries.BoolValue)
				{
					LogToFile(g_szQueryFile, "SQL_selectMapZonesCallback - szQuery: %s", szQuery);
				}
				g_dDb.Query(sql_zoneFixCallback, szQuery, _, DBPrio_Low);
				return;
			}
			else if (zoneTypeIdChecker[i][k][x] > 1)
			{
				char szerror[258];
				Format(szerror, 258, "[SurfTimer] Duplicate Stage Zone ID's on %s [ZoneGroup: %i, ZoneType: 3, ZoneTypeId: %i]", g_szMapName, k, x);
				LogError(szerror);
			}
		}

		RefreshZones();

		// Set mapzone count in group
		for (int x = 0; x < g_mapZoneGroupCount; x++)
			for (int k = 0; k < ZONEAMOUNT; k++)
				if (g_mapZonesTypeCount[x][k] > 0)
					g_mapZoneCountinGroup[x]++;

		if (!g_bServerDataLoaded)
			db_GetMapRecord_Pro();
	}
}

public void sql_zoneFixCallback(Database db, DBResultSet results, const char[] error, any zongeroup)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_zoneFixCallback): %s", error);
		return;
	}
	if (zongeroup == -1)
		db_selectMapZones();
	else
	{
		char szQuery[258];
		Format(szQuery, sizeof(szQuery), "DELETE FROM `ck_bonus` WHERE `mapname` = '%s' AND `zonegroup` = %i;", g_szMapName, zongeroup);
		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "sql_zoneFixCallback - szQuery: %s", szQuery);
		}
		g_dDb.Query(sql_zoneFixCallback2, szQuery, zongeroup, DBPrio_Low);
	}
}

public void sql_zoneFixCallback2(Database db, DBResultSet results, const char[] error, any zongeroup)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_zoneFixCallback2): %s", error);
		return;
	}

	char szQuery[258];
	Format(szQuery, sizeof(szQuery), "UPDATE ck_bonus SET zonegroup = zonegroup-1 WHERE `mapname` = '%s' AND `zonegroup` = %i;", g_szMapName, zongeroup);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "sql_zoneFixCallback2 - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_zoneFixCallback, szQuery, _, DBPrio_Low);
}

public void db_deleteZone(int client, int zoneid)
{
	char szQuery[258];
	Transaction tTransaction = new Transaction();

	Format(szQuery, sizeof(szQuery), sql_deleteZone, g_szMapName, zoneid);
	tTransaction.AddQuery(szQuery);

	Format(szQuery, sizeof(szQuery), "UPDATE ck_zones SET zoneid = zoneid-1 WHERE mapname = '%s' AND zoneid > %i", g_szMapName, zoneid);
	tTransaction.AddQuery(szQuery);

	g_dDb.Execute(tTransaction, SQLTxn_ZoneRemovalSuccess, SQLTxn_ZoneRemovalFailed, GetClientUserId(client));
}

public void SQLTxn_ZoneRemovalSuccess(Database db, int userid, int numQueries, DBResultSet[] results, any[] queryData)
{
	int client = GetClientOfUserId(userid);

	if (IsValidClient(client))
	{
		CPrintToChat(client, "%t", "SQL9", g_szChatPrefix);
	}

	PrintToServer("[SurfTimer] Zone Removed Succesfully");
}

public void SQLTxn_ZoneRemovalFailed(Database db, int userid, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	int client = GetClientOfUserId(userid);

	if (IsValidClient(client))
	{
		CPrintToChat(client, "%t", "SQL10", g_szChatPrefix, error);
	}
	PrintToServer("[SurfTimer] Zone Removal Failed. Error: %s", error);
	return;
}

/*==================================
=               MISC               =
==================================*/

public void db_insertLastPosition(int client, char szMapName[128], int stage, int zgroup)
{
	if (GetConVarBool(g_hcvarRestore) && !g_bRoundEnd && (StrContains(g_szSteamID[client], "STEAM_") != -1) && g_bTimerRunning[client])
	{
		Handle pack = CreateDataPack();
		WritePackCell(pack, GetClientUserId(client));
		WritePackString(pack, szMapName);
		WritePackString(pack, g_szSteamID[client]);
		WritePackCell(pack, stage);
		WritePackCell(pack, zgroup);
		char szQuery[512];
		Format(szQuery, sizeof(szQuery), "SELECT * FROM ck_playertemp WHERE steamid = '%s'", g_szSteamID[client]);
		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "db_insertLastPosition - szQuery: %s", szQuery);
		}
		g_dDb.Query(db_insertLastPositionCallback, szQuery, pack, DBPrio_Low);
	}
}

public void db_insertLastPositionCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_insertLastPositionCallback): %s", error);
		delete pack;
		return;
	}

	char szQuery[1024];
	char szMapName[128];
	char szSteamID[32];

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	ReadPackString(pack, szMapName, 128);
	ReadPackString(pack, szSteamID, 32);
	int stage = ReadPackCell(pack);
	int zgroup = ReadPackCell(pack);
	delete pack;

	if (IsValidClient(client))
	{
		if (!g_bTimerRunning[client])
		g_fPlayerLastTime[client] = -1.0;
		int tickrate = g_Server_Tickrate * 5 * 11;
		if (results.HasResults && results.FetchRow())
		{
			Format(szQuery, sizeof(szQuery), sql_updatePlayerTmp, g_fPlayerCordsLastPosition[client][0], g_fPlayerCordsLastPosition[client][1], g_fPlayerCordsLastPosition[client][2], g_fPlayerAnglesLastPosition[client][0], g_fPlayerAnglesLastPosition[client][1], g_fPlayerAnglesLastPosition[client][2], g_fPlayerLastTime[client], szMapName, tickrate, stage, zgroup, szSteamID);
			if (g_cLogQueries.BoolValue)
			{
				LogToFile(g_szQueryFile, "db_insertLastPositionCallback - szQuery: %s", szQuery);
			}
			g_dDb.Query(SQL_CheckCallback, szQuery, _, DBPrio_Low);
		}
		else
		{
			Format(szQuery, sizeof(szQuery), sql_insertPlayerTmp, g_fPlayerCordsLastPosition[client][0], g_fPlayerCordsLastPosition[client][1], g_fPlayerCordsLastPosition[client][2], g_fPlayerAnglesLastPosition[client][0], g_fPlayerAnglesLastPosition[client][1], g_fPlayerAnglesLastPosition[client][2], g_fPlayerLastTime[client], szSteamID, szMapName, tickrate, stage, zgroup);
			if (g_cLogQueries.BoolValue)
			{
				LogToFile(g_szQueryFile, "db_insertLastPositionCallback - szQuery: %s", szQuery);
			}
			g_dDb.Query(SQL_CheckCallback, szQuery, _, DBPrio_Low);
		}
	}
}

public void db_ViewLatestRecords(int client)
{
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_ViewLatestRecords - szQuery: %s", sql_selectLatestRecords);
	}
	g_dDb.Query(sql_selectLatestRecordsCallback, sql_selectLatestRecords, GetClientUserId(client), DBPrio_Low);
}

public void sql_selectLatestRecordsCallback(Database db, DBResultSet results, const char[] error, int userid)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_selectLatestRecordsCallback): %s", error);
		return;
	}

	int data = GetClientOfUserId(userid);

	if (IsValidClient(data))
	{

		char szName[64];
		char szMapName[64];
		char szDate[64];
		char szTime[32];
		float ftime;
		PrintToConsole(data, "----------------------------------------------------------------------------------------------------");
		PrintToConsole(data, "Last map records:");
		if (results.HasResults)
		{
			Menu menu = CreateMenu(LatestRecordsMenuHandler);
			SetMenuTitle(menu, "Recently Broken Records");

			int i = 1;
			char szItem[128];
			while (results.FetchRow())
			{
				results.FetchString(0, szName, 64);
				ftime = results.FetchFloat(1);
				FormatTimeFloat(data, ftime, 3, szTime, sizeof(szTime));
				results.FetchString(2, szMapName, 64);
				results.FetchString(3, szDate, 64);
				Format(szItem, sizeof(szItem), "%s - %s by %s (%s)", szMapName, szTime, szName, szDate);
				PrintToConsole(data, szItem);
				AddMenuItem(menu, "", szItem, ITEMDRAW_DISABLED);
				i++;
			}
			if (i == 1)
			{
				PrintToConsole(data, "No records found.");
				delete menu;
			}
			else
			{
				SetMenuOptionFlags(menu, MENUFLAG_BUTTON_EXIT);
				DisplayMenu(menu, data, MENU_TIME_FOREVER);
			}
		}
		else
		PrintToConsole(data, "No records found.");
		PrintToConsole(data, "----------------------------------------------------------------------------------------------------");
		CPrintToChat(data, "%t", "ConsoleOutput", g_szChatPrefix);
	}
}

public int LatestRecordsMenuHandler(Handle menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
		delete menu;
}

public void db_InsertLatestRecords(char szSteamID[32], char szName[128], float FinalTime)
{
	char szQuery[512];
	Format(szQuery, sizeof(szQuery), sql_insertLatestRecords, szSteamID, szName, FinalTime, g_szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_InsertLatestRecords - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_CheckCallback, szQuery, _, DBPrio_Low);
}

public void db_CalcAvgRunTime()
{
	char szQuery[256];
	Format(szQuery, sizeof(szQuery), sql_selectAVGruntimepro, g_szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_CalcAvgRunTime - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_db_CalcAvgRunTimeCallback, szQuery, _, DBPrio_Low);
}

public void SQL_db_CalcAvgRunTimeCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_db_CalcAvgRunTimeCallback): %s", error);

		if (!g_bServerDataLoaded && g_bhasBonus){
			db_CalcAvgRunTimeBonus();
		}
		else if (!g_bServerDataLoaded){
			db_CalculatePlayerCount(0);
		}

		return;
	}

	if (results.HasResults){
		while (results.FetchRow()){
			g_favg_maptime = results.FetchFloat(0);
		}
	}

	if (g_bhasBonus)
		db_CalcAvgRunTimeBonus();
	else
		db_CalculatePlayerCount(0);
}

public void db_CalcAvgRunTimeBonus()
{
	char szQuery[256];
	Format(szQuery, sizeof(szQuery), sql_selectAllBonusTimesinMap, g_szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_CalcAvgRunTimeBonus - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_db_CalcAvgRunBonusTimeCallback, szQuery, _, DBPrio_Low);
}

public void SQL_db_CalcAvgRunBonusTimeCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_db_CalcAvgRunTimeCallback): %s", error);
		if (!g_bServerDataLoaded)
		db_CalculatePlayerCount(0);
		return;
	}

	for (int i = 1; i < MAXZONEGROUPS; i++)
	g_fAvg_BonusTime[i] = 0.0;

	if (results.HasResults)
	{
		int zonegroup, runtimes[MAXZONEGROUPS];
		float runtime[MAXZONEGROUPS], time;
		while (results.FetchRow())
		{
			zonegroup = results.FetchInt(0);
			time = results.FetchFloat(1);
			if (time > 0.0)
			{
				runtime[zonegroup] += time;
				runtimes[zonegroup]++;
			}
		}

		for (int i = 1; i < MAXZONEGROUPS; i++)
		g_fAvg_BonusTime[i] = runtime[i] / runtimes[i];
	}

	if (!g_bServerDataLoaded)
		db_CalculatePlayerCount(0);

	return;
}

public void db_GetDynamicTimelimit()
{
	if (!GetConVarBool(g_hDynamicTimelimit))
	{
		if (!g_bServerDataLoaded)
			db_GetTotalStages();
		return;
	}
	char szQuery[256];
	Format(szQuery, sizeof(szQuery), sql_selectAllMapTimesinMap, g_szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_GetDynamicTimelimit - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_db_GetDynamicTimelimitCallback, szQuery, _, DBPrio_Low);
}


public void SQL_db_GetDynamicTimelimitCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_db_GetDynamicTimelimitCallback): %s", error);
		loadAllClientSettings();
		return;
	}

	if (results.HasResults)
	{
		int maptimes = 0;
		float total = 0.0, time = 0.0;
		while (results.FetchRow())
		{
			time = results.FetchFloat(0);
			if (time > 0.0)
			{
				total += time;
				maptimes++;
			}
		}
		// requires min. 5 map times
		if (maptimes > 5)
		{
			int scale_factor = 3;
			int avg = RoundToNearest((total) / 60.0 / float(maptimes));

			// scale factor
			if (avg <= 10)
			scale_factor = 5;
			if (avg <= 5)
			scale_factor = 8;
			if (avg <= 3)
			scale_factor = 10;
			if (avg <= 2)
			scale_factor = 12;
			if (avg <= 1)
			scale_factor = 14;

			avg = avg * scale_factor;

			// timelimit: min 20min, max 120min
			if (avg < 20)
			avg = 20;
			if (avg > 120)
			avg = 120;

			// set timelimit
			char szTimelimit[32];
			Format(szTimelimit, 32, "mp_timelimit %i;mp_roundtime %i", avg, avg);
			ServerCommand(szTimelimit);
			ServerCommand("mp_restartgame 1");
		}
		else
		ServerCommand("mp_timelimit 50");
	}

	if (!g_bServerDataLoaded)
		db_GetTotalStages();
		// loadAllClientSettings();

	return;
}

public void db_CalculatePlayerCount(int style)
{
	char szQuery[255];
	Format(szQuery, sizeof(szQuery), sql_CountRankedPlayers, style);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_CalculatePlayerCount - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_CountRankedPlayersCallback, szQuery, style, DBPrio_Low);
}

public void db_CalculatePlayersCountGreater0(int style)
{
	char szQuery[255];
	Format(szQuery, sizeof(szQuery), sql_CountRankedPlayers2, style);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_CalculatePlayersCountGreater0 - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_CountRankedPlayers2Callback, szQuery, style, DBPrio_Low);
}

public void sql_CountRankedPlayersCallback(Database db, DBResultSet results, const char[] error, any style)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_CountRankedPlayersCallback): %s", error);
		db_CalculatePlayersCountGreater0(style);
		return;
	}

	if (results.HasResults && results.FetchRow())
	{
		g_pr_AllPlayers[style] = results.FetchInt(0);
	}
	else
		g_pr_AllPlayers[style] = 1;

	// get amount of players with actual player points
	db_CalculatePlayersCountGreater0(style);
	return;
}

public void sql_CountRankedPlayers2Callback(Database db, DBResultSet results, const char[] error, any style)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_CountRankedPlayers2Callback): %s", error);

		if (!g_bServerDataLoaded)
			db_selectSpawnLocations();
		return;
	}

	if (results.HasResults && results.FetchRow())
	{
		g_pr_RankedPlayers[style] = results.FetchInt(0);
	}
	else
		g_pr_RankedPlayers[style] = 0;

	if (!g_bServerDataLoaded)
		db_selectSpawnLocations();

	return;
}

public void db_viewUnfinishedMaps(int client, char szSteamId[32])
{
	if (IsValidClient(client))
		CPrintToChat(client, "%t", "ConsoleOutput", g_szChatPrefix);
	else
		return;

	char szQuery[720];
	// Gets all players unfinished maps and bonuses from the database
	Format(szQuery, sizeof(szQuery), "SELECT mapname, zonegroup, zonename, (SELECT tier FROM ck_maptier d WHERE d.mapname = a.mapname) AS tier FROM ck_zones a WHERE (zonetype = 1 OR zonetype = 5) AND (SELECT runtimepro FROM ck_playertimes b WHERE b.mapname = a.mapname AND a.zonegroup = 0 AND b.style = %d AND steamid = '%s' UNION SELECT runtime FROM ck_bonus c WHERE c.mapname = a.mapname AND c.zonegroup = a.zonegroup AND c.style = %d AND steamid = '%s') IS NULL GROUP BY mapname, zonegroup ORDER BY tier, mapname, zonegroup ASC", g_ProfileStyleSelect[client], szSteamId, g_ProfileStyleSelect[client], szSteamId);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewUnfinishedMaps - szQuery: %s", szQuery);
	}
	g_dDb.Query(db_viewUnfinishedMapsCallback, szQuery, GetClientUserId(client), DBPrio_Low);
}

public void db_viewUnfinishedMapsCallback(Database db, DBResultSet results, const char[] error, any userid)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_viewUnfinishedMapsCallback): %s", error);
		return;
	}

	if (results.HasResults)
	{
		char szMap[128], szMap2[128], tmpMap[128], consoleString[1024], unfinishedBonusBuffer[772], zName[128];
		bool mapUnfinished, bonusUnfinished;
		int zGrp, count, mapCount, bonusCount, mapListSize = GetArraySize(g_MapList), digits;
		float time = 0.5;
		int tier;
		while (results.FetchRow())
		{
			// Get the map and check that it is in the mapcycle
			results.FetchString(0, szMap, 128);
			tier = results.FetchInt(3);
			for (int i = 0; i < mapListSize; i++)
			{
				GetArrayString(g_MapList, i, szMap2, 128);
				if (StrEqual(szMap, szMap2, false))
				{
					// Map is in the mapcycle, and is unfinished

					// Initialize the name
					if (!tmpMap[0])
					strcopy(tmpMap, 128, szMap);

					// Check if the map changed, if so announce to client's console
					if (!StrEqual(szMap, tmpMap, false))
					{
						if (count < 10)
						digits = 1;
						else
						if (count < 100)
						digits = 2;
						else
						digits = 3;

						if (strlen(tmpMap) < (13-digits)) // <- 11
							Format(tmpMap, 128, "%s - Tier %i:\t\t\t\t", tmpMap, tier);
						else if ((12-digits) < strlen(tmpMap) < (21-digits)) // 12 - 19
							Format(tmpMap, 128, "%s - Tier %i:\t\t\t", tmpMap, tier);
						else if ((20-digits) < strlen(tmpMap) < (28-digits)) // 20 - 25
							Format(tmpMap, 128, "%s - Tier %i:\t\t", tmpMap, tier);
						else
							Format(tmpMap, 128, "%s - Tier %i:\t", tmpMap, tier);

						count++;
						if (!mapUnfinished) // Only bonus is unfinished
						Format(consoleString, 1024, "%i. %s\t\t|  %s", count, tmpMap, unfinishedBonusBuffer);
						else if (!bonusUnfinished) // Only map is unfinished
						Format(consoleString, 1024, "%i. %sMap unfinished\t|", count, tmpMap);
						else // Both unfinished
						Format(consoleString, 1024, "%i. %sMap unfinished\t|  %s", count, tmpMap, unfinishedBonusBuffer);

						// Throttle messages to not cause errors on huge mapcycles
						time = time + 0.1;
						Handle pack = CreateDataPack();
						WritePackCell(pack, userid);
						WritePackString(pack, consoleString);
						CreateDataTimer(time, PrintUnfinishedLine, pack);

						mapUnfinished = false;
						bonusUnfinished = false;
						consoleString[0] = '\0';
						unfinishedBonusBuffer[0] = '\0';
						strcopy(tmpMap, 128, szMap);
					}

					zGrp = results.FetchInt(1);
					if (zGrp < 1)
					{
						mapUnfinished = true;
						mapCount++;
					}
					else
					{
						results.FetchString(2, zName, 128);

						if (!zName[0])
							Format(zName, 128, "bonus %i", zGrp);

						if (bonusUnfinished)
						Format(unfinishedBonusBuffer, 772, "%s, %s", unfinishedBonusBuffer, zName);
						else
						{
							bonusUnfinished = true;
							Format(unfinishedBonusBuffer, 772, "Bonus: %s", zName);
						}
						bonusCount++;
					}
					break;
				}
			}
		}

		int client = GetClientOfUserId(userid);
		
		if (IsValidClient(client))
		{
			PrintToConsole(client, " ");
			PrintToConsole(client, "------- User Stats -------");
			PrintToConsole(client, "%i unfinished maps of total %i maps", mapCount, g_pr_MapCount[0]);
			PrintToConsole(client, "%i unfinished bonuses", bonusCount);
			PrintToConsole(client, "SteamID: %s", g_szProfileSteamId[client]);
			PrintToConsole(client, "--------------------------");
			PrintToConsole(client, " ");
			PrintToConsole(client, "------------------------------ Map Details -----------------------------");
		}
	}
}

public Action PrintUnfinishedLine(Handle timer, DataPack pack)
{
	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	char teksti[1024];
	ReadPackString(pack, teksti, 1024);
	
	if (IsClientInGame(client))
	{
		PrintToConsole(client, teksti);
	}

}

public void sql_selectPlayerNameCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_selectPlayerNameCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int clientid = ReadPackCell(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	delete pack;

	if (results.HasResults && results.FetchRow())
	{
		results.FetchString(0, g_pr_szName[clientid], 64);
		g_bProfileRecalc[clientid] = true;

		if (IsValidClient(client))
		{
			PrintToConsole(client, "Profile refreshed (%s).", g_pr_szSteamID[clientid]);
		}
	}
	else if (IsValidClient(client))
	{
		PrintToConsole(client, "SteamID %s not found.", g_pr_szSteamID[clientid]);
	}
}

// 0. Admins counting players points starts here
public void RefreshPlayerRankTable(int max)
{
	g_pr_Recalc_ClientID = 1;
	g_pr_RankingRecalc_InProgress = true;
	char szQuery[255];

	// SELECT steamid, name from ck_playerrank where points > 0 ORDER BY points DESC";
	// SELECT steamid, name from ck_playerrank where points > 0 ORDER BY points DESC
	Format(szQuery, sizeof(szQuery), sql_selectRankedPlayers);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "RefreshPlayerRankTable - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_selectRankedPlayersCallback, szQuery, max, DBPrio_Low);
}

public void sql_selectRankedPlayersCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_selectRankedPlayersCallback): %s", error);
		return;
	}

	if (results.HasResults)
	{
		int i = 66;
		int x;
		g_pr_TableRowCount = results.RowCount;
		if (g_pr_TableRowCount == 0)
		{
			for (int c = 1; c <= MaxClients; c++)
			{
				if (IsValidClient(c))
				{
					if (g_bManualRecalc)
					{
						CPrintToChat(c, "%t", "PrUpdateFinished", g_szChatPrefix);
					}
				}
			}
				
			g_bManualRecalc = false;
			g_pr_RankingRecalc_InProgress = false;

			if (IsValidClient(g_pr_Recalc_AdminID))
			{
				PrintToConsole(g_pr_Recalc_AdminID, ">> Recalculation finished");
				CreateTimer(0.1, RefreshAdminMenu, GetClientUserId(g_pr_Recalc_AdminID), TIMER_FLAG_NO_MAPCHANGE);
			}
		}

		if (MAX_PR_PLAYERS != data && g_pr_TableRowCount > data)
			x = 66 + data;
		else
			x = 66 + g_pr_TableRowCount;

		if (g_pr_TableRowCount > MAX_PR_PLAYERS)
			g_pr_TableRowCount = MAX_PR_PLAYERS;

		if (x > MAX_PR_PLAYERS)
			x = MAX_PR_PLAYERS - 1;

		if (IsValidClient(g_pr_Recalc_AdminID) && g_bManualRecalc)
		{
			int max = MAX_PR_PLAYERS - 66;
			PrintToConsole(g_pr_Recalc_AdminID, " \n>> Recalculation started! (Only Top %i because of performance reasons)", max);
		}

		while (results.FetchRow())
		{
			if (i <= x)
			{
				g_pr_points[i][0] = 0;
				results.FetchString(0, g_pr_szSteamID[i], 32);
				results.FetchString(1, g_pr_szName[i], 64);

				g_bProfileRecalc[i] = true;
				i++;
			}
			if (i == x)
			{
				CalculatePlayerRank(66, 0);
			}
		}
	}
	else
		PrintToConsole(g_pr_Recalc_AdminID, " \n>> No valid players found!");
}

public void db_Cleanup()
{
	char szQuery[255];

	// tmps
	Format(szQuery, sizeof(szQuery), "DELETE FROM ck_playertemp where mapname != '%s'", g_szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_Cleanup - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_CheckCallback, szQuery, _, DBPrio_Low);

	// times
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_Cleanup - szQuery:DELETE FROM ck_playertimes where runtimepro = -1.0");
	}
	g_dDb.Query(SQL_CheckCallback, "DELETE FROM ck_playertimes where runtimepro = -1.0", _, DBPrio_Low);

	// fluffys pointless players
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_Cleanup - szQuery: DELETE FROM ck_playerrank WHERE `points` <= 0");
	}
	g_dDb.Query(SQL_CheckCallback, "DELETE FROM ck_playerrank WHERE `points` <= 0", _, DBPrio_Low);

}

public void SQL_InsertPlayerCallBack(Database db, DBResultSet results, const char[] error, int userid)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_InsertPlayerCallBack): %s", error);
		return;
	}

	int client = GetClientOfUserId(userid);
	if (IsClientInGame(client))
		db_UpdateLastSeen(client);
}

public void db_UpdateLastSeen(int client)
{
	if ((StrContains(g_szSteamID[client], "STEAM_") != -1) && !IsFakeClient(client))
	{
		char szQuery[512];
		Format(szQuery, sizeof(szQuery), sql_UpdateLastSeen, g_szSteamID[client]);
		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "db_UpdateLastSeen - szQuery: %s", szQuery);
		}
		g_dDb.Query(SQL_CheckCallback, szQuery, _, DBPrio_Low);
	}
}

/*===================================
=         DEFAULT CALLBACKS         =
===================================*/

public void SQL_CheckCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_CheckCallback): %s", error);
		return;
	}
}

/*==================================
=          PLAYER OPTIONS          =
==================================*/

public void db_viewPlayerOptions(int client, char szSteamId[32])
{
	g_bLoadedModules[client] = false;
	char szQuery[1024];
	Format(szQuery, sizeof(szQuery), sql_selectPlayerOptions, szSteamId);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewPlayerOptions - szQuery: %s", szQuery);
	}
	g_dDb.Query(db_viewPlayerOptionsCallback, szQuery, GetClientUserId(client), DBPrio_Low);
}

public void db_viewPlayerOptionsCallback(Database db, DBResultSet results, const char[] error, any userid)
{
	int client = GetClientOfUserId(userid);

	if (IsValidClient(client))
	{
		if (!IsValidDatabase(db, error))
		{
			LogError("[SurfTimer] SQL Error (db_viewPlayerOptionsCallback): %s", error);
			if (!g_bSettingsLoaded[client])
				LoadClientSetting(client, g_iSettingToLoad[client]);
			return;
		}

		if (results.HasResults && results.FetchRow())
		{
			// "SELECT timer, hide, sounds, chat, viewmodel, autobhop, checkpoints, gradient, speedmode, centrehud, module1c, module2c, module3c, module4c, module5c, module6c, sidehud, module1s, module2s, module3s, module4s, module5s, prestrafe FROM ck_playeroptions2 where steamid = '%s';"

			g_bTimerEnabled[client] = view_as<bool>(results.FetchInt(0));
			g_bHide[client] = view_as<bool>(results.FetchInt(1));
			g_bEnableQuakeSounds[client] = view_as<bool>(results.FetchInt(2));
			g_bHideChat[client] = view_as<bool>(results.FetchInt(3));
			g_bViewModel[client] = view_as<bool>(results.FetchInt(4));
			g_bAutoBhopClient[client] = view_as<bool>(results.FetchInt(5));
			g_bCheckpointsEnabled[client] = view_as<bool>(results.FetchInt(6));
			g_SpeedGradient[client] = results.FetchInt(7);
			g_SpeedMode[client] = results.FetchInt(8);
			g_bCenterSpeedDisplay[client] = view_as<bool>(results.FetchInt(9));
			g_bCentreHud[client] = view_as<bool>(results.FetchInt(10));
			g_iTeleSide[client] = results.FetchInt(11);
			g_iCentreHudModule[client][0] = results.FetchInt(12);
			g_iCentreHudModule[client][1] = results.FetchInt(13);
			g_iCentreHudModule[client][2] = results.FetchInt(14);
			g_iCentreHudModule[client][3] = results.FetchInt(15);
			g_iCentreHudModule[client][4] = results.FetchInt(16);
			g_iCentreHudModule[client][5] = results.FetchInt(17);
			g_bSideHud[client] = view_as<bool>(results.FetchInt(18));
			g_iSideHudModule[client][0] = results.FetchInt(19);
			g_iSideHudModule[client][1] = results.FetchInt(20);
			g_iSideHudModule[client][2] = results.FetchInt(21);
			g_iSideHudModule[client][3] = results.FetchInt(22);
			g_iSideHudModule[client][4] = results.FetchInt(23);
			g_iPrespeedText[client] = view_as<bool>(results.FetchInt(24));
			g_iCpMessages[client] = view_as<bool>(results.FetchInt(25));
			g_iWrcpMessages[client] = view_as<bool>(results.FetchInt(26));
			

			// Functionality for normal spec list
			if (g_iSideHudModule[client][0] == 5 && (g_iSideHudModule[client][1] == 0 && g_iSideHudModule[client][2] == 0 && g_iSideHudModule[client][3] == 0 && g_iSideHudModule[client][4] == 0))
				g_bSpecListOnly[client] = true;
			else
				g_bSpecListOnly[client] = false;
			
			g_bLoadedModules[client] = true;
		}
		else
		{
			char szQuery[512];

			// "INSERT INTO ck_playeroptions2 (steamid, timer, hide, sounds, chat, viewmodel, autobhop, checkpoints, centrehud, module1c, module2c, module3c, module4c, module5c, module6c, sidehud, module1s, module2s, module3s, module4s, module5s) VALUES('%s', '%i', '%i', '%i', '%i', '%i', '%i', '%i', '%i', '%i', '%i', '%i', '%i', '%i', '%i', '%i', '%i', '%i', '%i', '%i', '%i');";

			Format(szQuery, sizeof(szQuery), sql_insertPlayerOptions, g_szSteamID[client]);
			if (g_cLogQueries.BoolValue)
			{
				LogToFile(g_szQueryFile, "db_viewPlayerOptionsCallback - szQuery: %s", szQuery);
			}
			g_dDb.Query(SQL_CheckCallback, szQuery, _, DBPrio_Low);

			g_bTimerEnabled[client] = true;
			g_bHide[client] = false;
			g_bEnableQuakeSounds[client] = true;
			g_bHideChat[client] = false;
			g_bViewModel[client] = true;
			g_bAutoBhopClient[client] = true;
			g_bCheckpointsEnabled[client] = true;
			g_SpeedGradient[client] = 3;
			g_SpeedMode[client] = 0;
			g_bCenterSpeedDisplay[client] = false;
			g_bCentreHud[client] = true;
			g_iTeleSide[client] = 0;
			g_iCentreHudModule[client][0] = 1;
			g_iCentreHudModule[client][1] = 2;
			g_iCentreHudModule[client][2] = 3;
			g_iCentreHudModule[client][3] = 4;
			g_iCentreHudModule[client][4] = 5;
			g_iCentreHudModule[client][5] = 6;
			g_bSideHud[client] = true;
			g_iSideHudModule[client][0] = 5;
			g_iSideHudModule[client][1] = 0;
			g_iSideHudModule[client][2] = 0;
			g_iSideHudModule[client][3] = 0;
			g_iSideHudModule[client][4] = 0;
			g_bSpecListOnly[client] = true;
			g_iPrespeedText[client] = false;
			g_iCpMessages[client] = false;
			g_iWrcpMessages[client] = false;
		}

		if (!g_bSettingsLoaded[client])
		{
			g_fTick[client][1] = GetGameTime();
			float tick = g_fTick[client][1] - g_fTick[client][0];
			LogToFileEx(g_szLogFile, "[SurfTimer] %s: Finished db_viewPlayerOptions in %fs", g_szSteamID[client], tick);
			g_fTick[client][0] = GetGameTime();

			LoadClientSetting(client, g_iSettingToLoad[client]);
		}
	}
}

public void db_updatePlayerOptions(int client)
{
	char szQuery[1024];
	// "UPDATE ck_playeroptions2 SET timer = %i, hide = %i, sounds = %i, chat = %i, viewmodel = %i, autobhop = %i, checkpoints = %i, centrehud = %i, module1c = %i, module2c = %i, module3c = %i, module4c = %i, module5c = %i, module6c = %i, sidehud = %i, module1s = %i, module2s = %i, module3s = %i, module4s = %i, module5s = %i where steamid = '%s'";
	if (g_bSettingsLoaded[client] && g_bServerDataLoaded && g_bLoadedModules[client])
	{
		Format(szQuery, sizeof(szQuery), sql_updatePlayerOptions, BooltoInt(g_bTimerEnabled[client]), BooltoInt(g_bHide[client]), BooltoInt(g_bEnableQuakeSounds[client]), BooltoInt(g_bHideChat[client]), BooltoInt(g_bViewModel[client]), BooltoInt(g_bAutoBhopClient[client]), BooltoInt(g_bCheckpointsEnabled[client]), g_SpeedGradient[client], g_SpeedMode[client], BooltoInt(g_bCenterSpeedDisplay[client]), BooltoInt(g_bCentreHud[client]), g_iTeleSide[client], g_iCentreHudModule[client][0], g_iCentreHudModule[client][1], g_iCentreHudModule[client][2], g_iCentreHudModule[client][3], g_iCentreHudModule[client][4], g_iCentreHudModule[client][5], BooltoInt(g_bSideHud[client]), g_iSideHudModule[client][0], g_iSideHudModule[client][1], g_iSideHudModule[client][2], g_iSideHudModule[client][3], g_iSideHudModule[client][4], BooltoInt(g_iPrespeedText[client]), BooltoInt(g_iCpMessages[client]), BooltoInt(g_iWrcpMessages[client]), g_szSteamID[client]);
		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "db_updatePlayerOptions - szQuery: %s", szQuery);
		}
		g_dDb.Query(SQL_CheckCallback, szQuery, _, DBPrio_Low);
	}
}

/*===================================
=               MENUS               =
===================================*/

public void db_selectTopPlayers(int client, int style)
{
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, style);

	char szQuery[128];
	Format(szQuery, sizeof(szQuery), sql_selectTopPlayers, style);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectTopPlayers - szQuery: %s", szQuery);
	}
	g_dDb.Query(db_selectTop100PlayersCallback, szQuery, pack, DBPrio_Low);
}

public void db_selectTop100PlayersCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_selectTop100PlayersCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int data = GetClientOfUserId(ReadPackCell(pack));
	int style = ReadPackCell(pack);
	delete pack;

	if (IsValidClient(data))
	{
		char szValue[128];
		char szName[64];
		char szRank[16];
		char szSteamID[32];
		char szPerc[16];
		int points;
		Menu menu = new Menu(TopPlayersMenuHandler1);
		char szTitle[256];
		if (style == 0)
			Format(szTitle, sizeof(szTitle), "Top 100 Players\n    Rank   Points       Maps            Player");
		else
			Format(szTitle, sizeof(szTitle), "Top 100 Players - %s\n    Rank   Points       Maps            Player", g_szStyleMenuPrint[style]);

		menu.SetTitle(szTitle);
		menu.Pagination = 5;

		if (results.HasResults)
		{
			int i = 1;
			while (results.FetchRow())
			{
				results.FetchString(0, szName, 64);
				if (i == 100)
				Format(szRank, 16, "[%i.]", i);
				else
				if (i < 10)
				Format(szRank, 16, "[0%i.]  ", i);
				else
				Format(szRank, 16, "[%i.]  ", i);

				points = results.FetchInt(1);
				int pro = results.FetchInt(2);
				results.FetchString(3, szSteamID, 32);
				float fperc;
				fperc = (float(pro) / (float(g_pr_MapCount[0]))) * 100.0;

				if (fperc < 10.0)
				Format(szPerc, 16, "  %.1f%c  ", fperc, PERCENT);
				else
				if (fperc == 100.0)
				Format(szPerc, 16, "100.0%c", PERCENT);
				else
				if (fperc > 100.0) // player profile not refreshed after removing maps
				Format(szPerc, 16, "100.0%c", PERCENT);
				else
				Format(szPerc, 16, "%.1f%c  ", fperc, PERCENT);

				if (points < 10)
				Format(szValue, 128, "%s      %ip       %s     » %s", szRank, points, szPerc, szName);
				else
				if (points < 100)
				Format(szValue, 128, "%s     %ip       %s     » %s", szRank, points, szPerc, szName);
				else
				if (points < 1000)
				Format(szValue, 128, "%s   %ip       %s     » %s", szRank, points, szPerc, szName);
				else
				if (points < 10000)
				Format(szValue, 128, "%s %ip       %s     » %s", szRank, points, szPerc, szName);
				else
				if (points < 100000)
				Format(szValue, 128, "%s %ip     %s     » %s", szRank, points, szPerc, szName);
				else
				Format(szValue, 128, "%s %ip   %s     » %s", szRank, points, szPerc, szName);

				menu.AddItem(szSteamID, szValue, ITEMDRAW_DEFAULT);
				i++;
			}
			if (i == 1)
			{
				CPrintToChat(data, "%t", "NoPlayerTop", g_szChatPrefix);
			}
			else
			{
				menu.OptionFlags = MENUFLAG_BUTTON_EXIT;
				menu.Display(data, MENU_TIME_FOREVER);
			}
		}
		else
		{
			CPrintToChat(data, "%t", "NoPlayerTop", g_szChatPrefix);
		}
	}
}

public int TopPlayersMenuHandler1(Handle menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		GetMenuItem(menu, item, info, sizeof(info));
		g_MenuLevel[client] = 0;
		db_viewPlayerProfile(client, g_ProfileStyleSelect[client], info, true, "");
	}
	if (action == MenuAction_Cancel)
	{
		ckTopMenu(client, 0);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public int MapMenuHandler1(Handle menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		GetMenuItem(menu, item, info, sizeof(info));
		g_MenuLevel[client] = 1;
		db_viewPlayerProfile(client, g_ProfileStyleSelect[client], info, true, "");
	}
	if (action == MenuAction_Cancel)
	{
		ckTopMenu(client, g_ProfileStyleSelect[client]);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public int FinishedMapsMenuHandler(Handle menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Cancel)
	{
		ProfileMenu2(client, g_ProfileStyleSelect[client], "", g_szSteamID[client]);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

// fluffys sql select total bonus
public void db_selectTotalBonusCount()
{
	char szQuery[512];
	Format(szQuery, sizeof(szQuery), "SELECT COUNT(DISTINCT a.mapname,zonegroup) FROM ck_zones a RIGHT JOIN ck_maptier b ON a.mapname = b.mapname WHERE a.zonegroup > 0;");
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectTotalBonusCount - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_selectTotalBonusCountCallback, szQuery, _, DBPrio_Low);
}

public void sql_selectTotalBonusCountCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_selectTotalBonusCountCallback): %s", error);
		if (!g_bServerDataLoaded)
			db_selectTotalStageCount();
		return;
	}

	if (results.HasResults && results.FetchRow())
		g_pr_BonusCount = results.FetchInt(0);

	if (!g_bServerDataLoaded)
		db_selectTotalStageCount();

	return;
}

// fluffys sql select total stages
public void db_selectTotalStageCount()
{
	char szQuery[512];
	Format(szQuery, sizeof(szQuery), "SELECT SUM(c.stages) FROM (SELECT a.mapname, MAX(zonetypeid)+2 as stages FROM `ck_zones` a RIGHT JOIN ck_maptier b ON a.mapname = b.mapname WHERE zonetype = 3 GROUP BY a.mapname)c;");
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectTotalStageCount - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_selectTotalStageCountCallback, szQuery, _, DBPrio_Low);
}

public void sql_selectTotalStageCountCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_selectTotalBonusCountCallback): %s", error);

		if (!g_bServerDataLoaded)
			db_selectCurrentMapImprovement();
		return;
	}

	if (results.HasResults && results.FetchRow())
		g_pr_StageCount = results.FetchInt(0);

	g_pr_StageCount = g_pr_StageCount * 2;

	if (!g_bServerDataLoaded)
		db_selectCurrentMapImprovement();

	return;
}

public void db_selectWrcpRecord(int client, int style, int stage)
{
	if (!IsValidClient(client) || IsFakeClient(client) || g_bUsingStageTeleport[client])
		return;

	if (stage > g_TotalStages) // Hack fix for multiple end zones
		stage = g_TotalStages;

	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, style);
	WritePackCell(pack, stage);

	char szQuery[255];
	if (style == 0)
		Format(szQuery, sizeof(szQuery), "SELECT runtimepro FROM ck_wrcps WHERE steamid = '%s' AND mapname = '%s' AND stage = %i AND style = 0", g_szSteamID[client], g_szMapName, stage);
	else if (style != 0)
		Format(szQuery, sizeof(szQuery), "SELECT runtimepro FROM ck_wrcps WHERE steamid = '%s' AND mapname = '%s' AND stage = %i AND style = %i", g_szSteamID[client], g_szMapName, stage, style);

	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectWrcpRecord - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_selectWrcpRecordCallback, szQuery, pack, DBPrio_Low);
}

public void sql_selectWrcpRecordCallback(Database db, DBResultSet results, const char[] error, DataPack packx)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[Surftimer] SQL Error (sql_selectWrcpRecordCallback): %s", error);
		delete packx;
		return;
	}

	ResetPack(packx);
	int client = GetClientOfUserId(ReadPackCell(packx));
	int style = ReadPackCell(packx);
	int stage = ReadPackCell(packx);
	delete packx;

	if (!IsValidClient(client) || IsFakeClient(client))
	{
		return;
	}

	char szName[MAX_NAME_LENGTH];
	GetClientName(client, szName, MAX_NAME_LENGTH);

	char szQuery[1024];

	if (stage > g_TotalStages) // Hack fix for multiple end zones
		stage = g_TotalStages;

	char sz_srDiff[128];
	char szDiff[128];
	float time = g_fFinalWrcpTime[client];
	float f_srDiff;
	float fDiff;

	// PB
	fDiff = (g_fWrcpRecord[client][stage][style] - time);
	FormatTimeFloat(client, fDiff, 3, szDiff, 128);

	if (fDiff > 0)
		Format(szDiff, 128, "%cPB: %c-%s%c", WHITE, LIGHTGREEN, szDiff, WHITE);
	else
		Format(szDiff, 128, "%cPB: %c+%s%c", WHITE, RED, szDiff, WHITE);

	// SR
	if (style == 0)
		f_srDiff = (g_fStageRecord[stage] - time);
	else // styles
		f_srDiff = (g_fStyleStageRecord[style][stage] - time);

	FormatTimeFloat(client, f_srDiff, 3, sz_srDiff, 128);

	if (f_srDiff > 0)
		Format(sz_srDiff, 128, "%cWR: %c-%s%c", WHITE, LIGHTGREEN, sz_srDiff, WHITE);
	else
		Format(sz_srDiff, 128, "%cWR: %c+%s%c", WHITE, RED, sz_srDiff, WHITE);

	// Found old time from database
	if (results.HasResults && results.FetchRow())
	{
		float stagetime = results.FetchFloat(0);

		// If old time was slower than the new time, update record
		if ((g_fFinalWrcpTime[client] <= stagetime || stagetime <= 0.0))
		{
			db_updateWrcpRecord(client, style, stage);
		}
		else
		{ // fluffys come back
			char szSpecMessage[512];

			g_bStageSRVRecord[client][stage] = false;
			if (style == 0)
			{
				CPrintToChat(client, "%t", "SQL11", g_szChatPrefix, stage, g_szFinalWrcpTime[client], szDiff, sz_srDiff);

				Format(szSpecMessage, sizeof(szSpecMessage), "%t", "SQL12", g_szChatPrefix, szName, stage, g_szFinalWrcpTime[client], szDiff, sz_srDiff);
			}
			else if (style != 0) // styles
			{
				CPrintToChat(client, "%t", "SQL13", g_szChatPrefix, stage, g_szStyleRecordPrint[style], g_szFinalWrcpTime[client], sz_srDiff, g_StyleStageRank[style][client][stage], g_TotalStageStyleRecords[style][stage]);
				Format(szSpecMessage, sizeof(szSpecMessage), "%t", "SQL14", g_szChatPrefix, stage, g_szStyleRecordPrint[style], g_szFinalWrcpTime[client], sz_srDiff, g_StyleStageRank[style][client][stage], g_TotalStageStyleRecords[style][stage]);
			}
			CheckpointToSpec(client, szSpecMessage);

			if (g_bRepeat[client])
			{
				if (stage <= 1)
					Command_Restart(client, 1);
				else
					teleportClient(client, 0, stage, false);
			}
		}
	}
	else
	{ // No record found from database - Let's insert

		// Escape name for SQL injection protection
		char szName2[MAX_NAME_LENGTH * 2 + 1];
		g_dDb.Escape(szName, szName2, MAX_NAME_LENGTH * 2 + 1);

		// Move required information in datapack
		Handle pack = CreateDataPack();
		WritePackFloat(pack, g_fFinalWrcpTime[client]);
		WritePackCell(pack, style);
		WritePackCell(pack, stage);
		WritePackCell(pack, 1);
		WritePackCell(pack, GetClientUserId(client));

		if (style == 0)
			Format(szQuery, sizeof(szQuery), sql_insertNewWrcp, g_szSteamID[client], szName2, g_szMapName, g_fFinalWrcpTime[client], stage, g_iWrcpVelsStartNew[client][stage][0], g_iWrcpVelsStartNew[client][stage][1], g_iWrcpVelsStartNew[client][stage][2], g_iWrcpVelsEndNew[client][stage][0], g_iWrcpVelsEndNew[client][stage][1], g_iWrcpVelsEndNew[client][stage][2]);
		else if (style != 0)
			Format(szQuery, sizeof(szQuery), sql_insertNewWrcpStyle, g_szSteamID[client], szName2, g_szMapName, g_fFinalWrcpTime[client], stage, style, g_iWrcpVelsStartNew[client][stage][0], g_iWrcpVelsStartNew[client][stage][1], g_iWrcpVelsStartNew[client][stage][2], g_iWrcpVelsEndNew[client][stage][0], g_iWrcpVelsEndNew[client][stage][1], g_iWrcpVelsEndNew[client][stage][2]);

		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "sql_selectWrcpRecordCallback - szQuery: %s", szQuery);
		}
		g_dDb.Query(SQL_UpdateWrcpRecordCallback, szQuery, pack, DBPrio_Low);

		g_bStageSRVRecord[client][stage] = false;
	}
}

// If latest record was faster than old - Update time
public void db_updateWrcpRecord(int client, int style, int stage)
{
	if (!IsValidClient(client) || IsFakeClient(client))
		return;

	char szUName[MAX_NAME_LENGTH];
	GetClientName(client, szUName, MAX_NAME_LENGTH);

	// Also updating name in database, escape string
	char szName[MAX_NAME_LENGTH * 2 + 1];
	g_dDb.Escape(szUName, szName, MAX_NAME_LENGTH * 2 + 1);
	// int stage = g_CurrentStage[client];

	// Packing required information for later
	Handle pack = CreateDataPack();
	WritePackFloat(pack, g_fFinalWrcpTime[client]);
	WritePackCell(pack, style);
	WritePackCell(pack, stage);
	WritePackCell(pack, 0);
	WritePackCell(pack, GetClientUserId(client));

	char szQuery[1024];
	// "UPDATE ck_playertimes SET name = '%s', runtimepro = '%f' WHERE steamid = '%s' AND mapname = '%s';";
	if (style == 0)
		Format(szQuery, sizeof(szQuery), sql_updateWrcp, szName, g_fFinalWrcpTime[client], g_iWrcpVelsStartNew[client][stage][0], g_iWrcpVelsStartNew[client][stage][1], g_iWrcpVelsStartNew[client][stage][2], g_iWrcpVelsEndNew[client][stage][0], g_iWrcpVelsEndNew[client][stage][1], g_iWrcpVelsEndNew[client][stage][2], g_szSteamID[client], g_szMapName, stage);
	if (style > 0)
		Format(szQuery, sizeof(szQuery), sql_updateWrcpStyle, szName, g_fFinalWrcpTime[client], g_iWrcpVelsStartNew[client][stage][0], g_iWrcpVelsStartNew[client][stage][1], g_iWrcpVelsStartNew[client][stage][2], g_iWrcpVelsEndNew[client][stage][0], g_iWrcpVelsEndNew[client][stage][1], g_iWrcpVelsEndNew[client][stage][2], g_szSteamID[client], g_szMapName, stage, style);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_updateWrcpRecord - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_UpdateWrcpRecordCallback, szQuery, pack, DBPrio_Low);
}


public void SQL_UpdateWrcpRecordCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[Surftimer] SQL Error (SQL_UpdateWrcpRecordCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	float stagetime = ReadPackFloat(pack);
	int style = ReadPackCell(pack);
	int stage = ReadPackCell(pack);
	int zero = ReadPackCell(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));

	if (IsValidClient(client))
	{
		// DONT LOOK WTF IS WRONG WITH ME
		int zero2 = 0;
		if (zero == 0)
			zero2 = 0;

		for (int i = zero2; i < 3; i++)
		{
			g_iWrcpVelsStartRecord[client][stage][i] = g_iWrcpVelsStartNew[client][stage][i];
			g_iWrcpVelsEndRecord[client][stage][i] = g_iWrcpVelsEndNew[client][stage][i];
		}

		// Find out how many times are are faster than the players time
		char szQuery[512];
		if (style == 0)
			Format(szQuery, sizeof(szQuery), sql_selectFasterWrcps, g_szMapName, stage, stagetime);
		else if (style != 0)
			Format(szQuery, sizeof(szQuery), sql_selectFasterWrcpsStyle, g_szMapName, stagetime, stage, style);

		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "SQL_UpdateWrcpRecordCallback - szQuery: %s", szQuery);
		}
		g_dDb.Query(SQL_UpdateWrcpRecordCallback2, szQuery, pack, DBPrio_Low);
	}
}

public void SQL_UpdateWrcpRecordCallback2(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_UpdateWrcpRecordCallback2): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	float time = ReadPackFloat(pack);
	int style = ReadPackCell(pack);
	int stage = ReadPackCell(pack);
	bool bInsert = view_as<bool>(ReadPackCell(pack));
	int client = GetClientOfUserId(ReadPackCell(pack));
	delete pack;

	if (IsValidClient(client))
	{
		if (bInsert) // fluffys FIXME
		{
			if (style == 0)
				g_TotalStageRecords[stage]++;
			else
				g_TotalStageStyleRecords[style][stage]++;
		}

		if (stage == 0)
			return;

		// Get players rank, 9999999 = error
		int stagerank = 9999999;
		if (results.HasResults && results.FetchRow())
			stagerank = results.FetchInt(0) + 1;

		if (stage > g_TotalStages) // Hack Fix for multiple end zone issue
			stage = g_TotalStages;

		if (style == 0)
			g_StageRank[client][stage] = stagerank;
		else
			g_StyleStageRank[style][client][stage] = stagerank;

		// Get client name
		char szName[MAX_NAME_LENGTH];
		GetClientName(client, szName, MAX_NAME_LENGTH);

		char sz_srDiff[128];

		// PB
		char szDiff[128];
		float fDiff;

		fDiff = (g_fWrcpRecord[client][stage][style] - time);
		FormatTimeFloat(client, fDiff, 3, szDiff, 128);

		if (g_fWrcpRecord[client][stage][style] != -1.0) // Existing stage time
		{
			if (fDiff > 0)
				Format(szDiff, 128, "%cPB: %c-%s%c", WHITE, LIGHTGREEN, szDiff, WHITE);
			else
				Format(szDiff, 128, "%cPB: %c+%s%c", WHITE, RED, szDiff, WHITE);
		}
		else
		{
			Format(szDiff, 128, "%cPB: %c%s%c", WHITE, LIMEGREEN, g_szFinalWrcpTime[client], WHITE);
		}

		// SR
		float f_srDiff;
		if (style == 0)
			f_srDiff = (g_fStageRecord[stage] - time);
		else if (style != 0)
			f_srDiff = (g_fStyleStageRecord[style][stage] - time);

		FormatTimeFloat(client, f_srDiff, 3, sz_srDiff, 128);

		if (f_srDiff > 0)
			Format(sz_srDiff, 128, "%cSR: %c-%s%c", WHITE, LIGHTGREEN, sz_srDiff, WHITE);
		else
			Format(sz_srDiff, 128, "%cSR: %c+%s%c", WHITE, RED, sz_srDiff, WHITE);

		// Check for SR
		bool newRecordHolder = false;
		if (style == 0)
		{
			if (g_TotalStageRecords[stage] > 0)
			{ // If the server already has a record

				if (g_fFinalWrcpTime[client] < g_fStageRecord[stage] && g_fFinalWrcpTime[client] > 0.0)
				{ 
					// New fastest time in map
					g_bStageSRVRecord[client][stage] = true;
					if (g_fWrcpRecord[client][stage][0] != g_fStageRecord[stage])
						newRecordHolder = true;
					g_fStageRecord[stage] = g_fFinalTime[client];
					Format(g_szStageRecordPlayer[stage], MAX_NAME_LENGTH, "%s", szName);
					FormatTimeFloat(1, g_fStageRecord[stage], 3, g_szRecordStageTime[stage], 64);
					CPrintToChatAll("%t", "SQL15", g_szChatPrefix, szName, stage, g_szFinalWrcpTime[client], sz_srDiff, g_TotalStageRecords[stage]);
					g_bSavingWrcpReplay[client] = true;
					// Stage_SaveRecording(client, stage, g_szFinalWrcpTime[client]);
					PlayWRCPRecord(1);
				}
				else
				{
					CPrintToChat(client, "%t", "SQL16", g_szChatPrefix, stage, g_szFinalWrcpTime[client], szDiff, sz_srDiff, g_StageRank[client][stage], g_TotalStageRecords[stage]);

					char szSpecMessage[512];
					Format(szSpecMessage, sizeof(szSpecMessage), "%t", "SQL17", g_szChatPrefix, szName, stage, g_szFinalWrcpTime[client], szDiff, sz_srDiff, g_StageRank[client][stage], g_TotalStageRecords[stage]);
					CheckpointToSpec(client, szSpecMessage);
				}
			}
			else
			{
				// Has to be the new record, since it is the first completion
				newRecordHolder = true;
				g_bStageSRVRecord[client][stage] = true;
				g_fStageRecord[stage] = g_fFinalTime[client];
				Format(g_szStageRecordPlayer[stage], MAX_NAME_LENGTH, "%s", szName);
				FormatTimeFloat(1, g_fStageRecord[stage], 3, g_szRecordStageTime[stage], 64);

				CPrintToChatAll("%t", "SQL18", g_szChatPrefix, szName, stage, g_szFinalWrcpTime[client]);
				g_bSavingWrcpReplay[client] = true;
				// Stage_SaveRecording(client, stage, g_szFinalWrcpTime[client]);
				PlayWRCPRecord(1);
			}
		}
		else if (style != 0) // styles
		{
			if (g_TotalStageStyleRecords[style][stage] > 0)
			{
				// If the server already has a record
				if (g_fFinalWrcpTime[client] < g_fStyleStageRecord[style][stage] && g_fFinalWrcpTime[client] > 0.0)
				{
					// New fastest time in map
					g_bStageSRVRecord[client][stage] = true;
					if (g_fWrcpRecord[client][stage][style] != g_fStyleStageRecord[style][stage])
						newRecordHolder = true;

					g_fStyleStageRecord[style][stage] = g_fFinalTime[client];
					Format(g_szStyleStageRecordPlayer[style][stage], MAX_NAME_LENGTH, "%s", szName);
					FormatTimeFloat(1, g_fStyleStageRecord[style][stage], 3, g_szStyleRecordStageTime[style][stage], 64);

					CPrintToChatAll("%t", "SQL19", g_szChatPrefix, szName, g_szStyleRecordPrint[style], stage, g_szFinalWrcpTime[client], sz_srDiff, g_StyleStageRank[style][client][stage], g_TotalStageStyleRecords[style][stage]);
					PlayWRCPRecord(1);
				}
				else
				{
					CPrintToChat(client, "%t", "SQL20", g_szChatPrefix, stage, g_szStyleRecordPrint[style], g_szFinalWrcpTime[client], sz_srDiff, g_StyleStageRank[style][client][stage], g_TotalStageStyleRecords[style][stage]);

					char szSpecMessage[512];
					Format(szSpecMessage, sizeof(szSpecMessage), "%t", "SQL21", g_szChatPrefix, stage, g_szStyleRecordPrint[style], g_szFinalWrcpTime[client], sz_srDiff, g_StyleStageRank[style][client][stage], g_TotalStageStyleRecords[style][stage]);
					CheckpointToSpec(client, szSpecMessage);
				}
			}
			else
			{
				// Has to be the new record, since it is the first completion
				g_bStageSRVRecord[client][stage] = true;
				newRecordHolder = true;
				g_fStyleStageRecord[style][stage] = g_fFinalTime[client];
				Format(g_szStyleStageRecordPlayer[style][stage], MAX_NAME_LENGTH, "%s", szName);
				FormatTimeFloat(1, g_fStyleStageRecord[style][stage], 3, g_szStyleRecordStageTime[style][stage], 64);

				CPrintToChatAll("%t", "SQL22", g_szChatPrefix, szName, g_szStyleRecordPrint[style], stage, g_szFinalWrcpTime[client]);
				PlayWRCPRecord(1);
			}
		}

		// Check if new record and if someone else had the old record, if so give them points
		if (g_bStageSRVRecord[client][stage])
		{
			int points = GetConVarInt(g_hWrcpPoints);
			if (style == 0)
			{
				if (newRecordHolder)
				{
					if (points > 0)
					{
						g_pr_oldpoints[client][0] = g_pr_points[client][0];
						g_pr_points[client][0] += points;
						int diff = g_pr_points[client][0] - g_pr_oldpoints[client][0];
						CPrintToChat(client, "%t", "EarnedPoints", g_szChatPrefix, szName, diff, g_pr_points[client][0]);
					}
				}
			}
			else
			{
				if (newRecordHolder)
				{
					if (points > 0)
					{
						g_pr_oldpoints[client][style] = g_pr_points[client][style];
						g_pr_points[client][style] += points;
						int diff = g_pr_points[client][style] - g_pr_oldpoints[client][style];
						CPrintToChat(client, "%t", "EarnedPoints2", g_szChatPrefix, szName, diff, g_szStyleRecordPrint[style], g_pr_points[client][style]);
					}
				}
			}
		}

		g_fWrcpRecord[client][stage][style] = time;

		db_viewStageRecords();

		if (g_bRepeat[client])
		{
			if (stage <= 1)
				Command_Restart(client, 1);
			else
				teleportClient(client, 0, stage, false);
		}
	}
}

// Get players stage rank in current map
public void db_viewPersonalStageRecords(int client, char szSteamId[32])
{
	if (!g_bSettingsLoaded[client] && !g_bhasStages)
	{
		LogToFileEx(g_szLogFile, "[Surftimer] %s: Skipping db_viewPersonalStageRecords (linear map)", g_szSteamID[client]);
		LoadClientSetting(client, 3);
		return;
	}

	char szQuery[1024];
	Format(szQuery, sizeof(szQuery), sql_selectStageTimes, szSteamId, g_szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewPersonalStageRecords - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_selectPersonalStageRecordsCallback, szQuery, GetClientUserId(client), DBPrio_Low);
}

public void SQL_selectPersonalStageRecordsCallback(Database db, DBResultSet results, const char[] error, any userid)
{
	int client = GetClientOfUserId(userid);

	if (IsValidClient(client))
	{
		if (!IsValidDatabase(db, error))
		{
			LogError("[Surftimer] SQL Error (SQL_selectPersonalStageRecordsCallback): %s", error);
			if (!g_bSettingsLoaded[client])
				LoadClientSetting(client, g_iSettingToLoad[client]);
			return;
		}

		int style;
		int stage;
		float time;

		for (int i = 0; i < CPLIMIT; i++)
		{
			for (int k = 0; k < 3; k++)
			{
				g_iWrcpVelsStartRecord[client][i][k] = 0;
				g_iWrcpVelsEndRecord[client][i][k] = 0;
			}

			for (int s = 0; s < MAX_STYLES; s++)
			{
				g_fWrcpRecord[client][i][s] = -1.0;
			}
		}

		if (results.HasResults)
		{
			while (results.FetchRow())
			{
				stage = results.FetchInt(1);
				style = results.FetchInt(2);
				time = results.FetchFloat(0);
				g_iWrcpVelsStartRecord[client][stage][0] = results.FetchInt(3);
				g_iWrcpVelsStartRecord[client][stage][1] = results.FetchInt(4);
				g_iWrcpVelsStartRecord[client][stage][2] = results.FetchInt(5);
				g_iWrcpVelsEndRecord[client][stage][0] = results.FetchInt(6);
				g_iWrcpVelsEndRecord[client][stage][1] = results.FetchInt(7);
				g_iWrcpVelsEndRecord[client][stage][2] = results.FetchInt(8);


				g_fWrcpRecord[client][stage][style] = time;

				if (style == 0)
				{
					db_viewStageRanks(client, stage);
				}
				else
				{
					db_viewStyleStageRanks(client, stage, style);
				}
			}
		}

		if (!g_bSettingsLoaded[client])
		{
			g_fTick[client][1] = GetGameTime();
			float tick = g_fTick[client][1] - g_fTick[client][0];
			LogToFileEx(g_szLogFile, "[Surftimer] %s: Finished db_viewPersonalStageRecords in %fs", g_szSteamID[client], tick);
			g_fTick[client][0] = GetGameTime();

			LoadClientSetting(client, g_iSettingToLoad[client]);
		}
	}
}

public void db_viewStageRanks(int client, int stage)
{
	if (!IsValidClient(client))
		return;

	char szQuery[512];

	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, stage);

	// "SELECT name,mapname FROM ck_playertimes WHERE runtimepro <= (SELECT runtimepro FROM ck_playertimes WHERE steamid = '%s' AND mapname = '%s' AND runtimepro > -1.0) AND mapname = '%s' AND runtimepro > -1.0 ORDER BY runtimepro;";
	// SELECT name FROM ck_bonus WHERE runtime <= (SELECT runtime FROM ck_bonus WHERE steamid = '%s' AND mapname= '%s' AND runtime > 0.0 AND zonegroup = %i) AND mapname = '%s' AND zonegroup = %i;
	Format(szQuery, sizeof(szQuery), "SELECT COUNT(*) FROM ck_wrcps WHERE runtimepro <= (SELECT runtimepro FROM ck_wrcps WHERE steamid = '%s' AND mapname = '%s' AND runtimepro > -1.0 AND stage = %i AND style = 0) AND mapname = '%s' AND stage = %i AND style = 0 AND runtimepro > -1.0;", g_szSteamID[client], g_szMapName, stage, g_szMapName, stage);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewStageRanks - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_viewStageRanksCallback, szQuery, pack, DBPrio_Low);
}

public void sql_viewStageRanksCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_viewStageRanksCallback): %s ", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int stage = ReadPackCell(pack);
	delete pack;

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			g_StageRank[client][stage] = results.FetchInt(0);
		}
	}
}

// Get Total Stages
public void db_GetTotalStages()
{
	// Check if map has stages, if not don't bother loading this
	if (!g_bhasStages)
	{
		db_selectTotalBonusCount();
		return;
	}

	char szQuery[512];

	Format(szQuery, sizeof(szQuery), "SELECT COUNT(`zonetype`) AS stages FROM `ck_zones` WHERE `zonetype` = '3' AND `mapname` = '%s'", g_szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_GetTotalStages - szQuery: %s", szQuery);
	}
	g_dDb.Query(db_GetTotalStagesCallback, szQuery, _, DBPrio_Low);
}

public void db_GetTotalStagesCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[Surftimer] SQL Error (db_GetTotalStagesCallback): %s ", error);
		db_viewStageRecords();
		return;
	}

	if (results.HasResults && results.FetchRow())
	{
		g_TotalStages = results.FetchInt(0) + 1;

		for(int i = 1; i <= g_TotalStages; i++)
		{
			g_fStageRecord[i] = 0.0;
			g_iWrcpVelsStartServerRecord[i][0] = 0;
			g_iWrcpVelsStartServerRecord[i][1] = 0;
			g_iWrcpVelsStartServerRecord[i][2] = 0;
			g_iWrcpVelsEndServerRecord[i][0] = 0;
			g_iWrcpVelsEndServerRecord[i][1] = 0;
			g_iWrcpVelsEndServerRecord[i][2] = 0;
			// fluffys comeback yo
		}
	}

	if (!g_bServerDataLoaded)
		db_viewStageRecords();
}

public void db_viewWrcpMap(int client, char mapname[128])
{
	char szQuery[1024];
	Format(szQuery, sizeof(szQuery), "SELECT `mapname`, COUNT(`zonetype`) AS stages FROM `ck_zones` WHERE `zonetype` = '3' AND `mapname` = (SELECT DISTINCT `mapname` FROM `ck_zones` WHERE `zonetype` = '3' AND `mapname` LIKE '%c%s%c' LIMIT 0, 1)", PERCENT, g_szWrcpMapSelect[client], PERCENT);
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackString(pack, mapname);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewWrcpMap - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_viewWrcpMapCallback, szQuery, pack, DBPrio_Low);
}

public void sql_viewWrcpMapCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_viewWrcpMapCallback): %s ", error);
		delete pack;
		return;
	}

	int totalstages;
	char mapnameresult[128];
	char stage[MAXPLAYERS + 1];
	char szStageString[MAXPLAYERS + 1];
	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	char mapname[128];
	ReadPackString(pack, mapname, 128);
	delete pack;

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			totalstages = results.FetchInt(1) + 1;
			results.FetchString(0, mapnameresult, 128);
			if (totalstages == 0 || totalstages == 1)
			{
				CPrintToChat(client, "%t", "SQL23", g_szChatPrefix, mapname);
				return;
			}

			if (pack != INVALID_HANDLE)
			{
				g_szWrcpMapSelect[client] = mapnameresult;
				Menu menu = CreateMenu(StageSelectMenuHandler);
				SetMenuTitle(menu, "%s: select a stage\n------------------------------\n", mapnameresult);
				int stageCount = totalstages;
				for (int i = 1; i <= stageCount; i++)
				{
					stage[0] = i;
					Format(szStageString, sizeof(szStageString), "Stage %i", i);
					AddMenuItem(menu, stage[0], szStageString);
				}
				g_bSelectWrcp[client] = true;
				SetMenuOptionFlags(menu, MENUFLAG_BUTTON_EXIT);
				DisplayMenu(menu, client, MENU_TIME_FOREVER);
				return;
			}
		}
	}
}

public void db_viewWrcpMapRecord(int client)
{
	char szQuery[1024];
	Format(szQuery, sizeof(szQuery), "SELECT name, MIN(runtimepro) FROM ck_wrcps WHERE mapname = '%s' AND runtimepro > -1.0 AND stage = %s AND style = 0;", g_szMapName, g_szWrcpMapSelect[client]);

	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewWrcpMapRecord - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_viewWrcpMapRecordCallback, szQuery, GetClientUserId(client), DBPrio_Low);
}

public void sql_viewWrcpMapRecordCallback(Database db, DBResultSet results, const char[] error, any userid)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_viewWrcpMapRecordCallback): %s ", error);
	}

	int client = GetClientOfUserId(userid);

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			if (results.IsFieldNull(1))
			{
				CPrintToChat(client, "%t", "SQL24", g_szChatPrefix);
				return;
			}

			char szName[MAX_NAME_LENGTH];
			float runtimepro;
			char szRuntimepro[64];

			results.FetchString(0, szName, 128);
			runtimepro = results.FetchFloat(1);
			FormatTimeFloat(0, runtimepro, 3, szRuntimepro, 64);

			CPrintToChat(client, "%t", "SQL25", g_szChatPrefix, szName, szRuntimepro, g_szWrcpMapSelect[client], g_szMapName);
			return;
		}
		else
		{
			CPrintToChat(client, "%t", "SQL24", g_szChatPrefix);
		}
	}
}

public void db_selectStageTopSurfers(int client, char info[32], char mapname[128])
{
	char szQuery[1024];
	Format(szQuery, sizeof(szQuery), "SELECT db2.steamid, db1.name, db2.runtimepro as overall, db1.steamid, db2.mapname FROM ck_wrcps as db2 INNER JOIN ck_playerrank as db1 on db2.steamid = db1.steamid WHERE db2.mapname = '%s' AND db2.runtimepro > -1.0 AND db2.stage = %i AND db1.style = 0 AND db2.style = 0 ORDER BY overall ASC LIMIT 50;", mapname, info);
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	// WritePackCell(pack, stage);
	WritePackString(pack, info);
	WritePackString(pack, mapname);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectStageTopSurfers - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_selectStageTopSurfersCallback, szQuery, pack, DBPrio_Low);
}

public void sql_selectStageTopSurfersCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_selectStageTopSurfersCallback): %s ", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	char stage[32];
	ReadPackString(pack, stage, 32);
	char mapname[128];
	ReadPackString(pack, mapname, 128);
	delete pack;

	if (IsValidClient(client))
	{
		char szSteamID[32];
		char szName[64];
		float time;
		char szMap[128];
		char szValue[128];
		char lineBuf[256];
		Handle stringArray = CreateArray(100);
		Handle menu;
		menu = CreateMenu(StageTopMenuHandler);
		SetMenuPagination(menu, 5);
		bool bduplicat = false;
		char title[256];
		if (results.HasResults)
		{
			int i = 1;
			while (results.FetchRow())
			{
				bduplicat = false;
				results.FetchString(0, szSteamID, 32);
				results.FetchString(1, szName, 64);
				time = results.FetchFloat(2);
				results.FetchString(4, szMap, 128);
				if (i == 1 || (i > 1))
				{
					int stringArraySize = GetArraySize(stringArray);
					for (int x = 0; x < stringArraySize; x++)
					{
						GetArrayString(stringArray, x, lineBuf, sizeof(lineBuf));
						if (StrEqual(lineBuf, szName, false))
						bduplicat = true;
					}
					if (bduplicat == false && i < 51)
					{
						char szTime[32];
						FormatTimeFloat(client, time, 3, szTime, sizeof(szTime));
						if (time < 3600.0)
						Format(szTime, 32, "   %s", szTime);
						if (i == 100)
						Format(szValue, 128, "[%i.] %s |    » %s", i, szTime, szName);
						if (i >= 10)
						Format(szValue, 128, "[%i.] %s |    » %s", i, szTime, szName);
						else
						Format(szValue, 128, "[0%i.] %s |    » %s", i, szTime, szName);
						AddMenuItem(menu, szSteamID, szValue, ITEMDRAW_DEFAULT);
						PushArrayString(stringArray, szName);
						i++;
					}
				}
			}
			if (i == 1)
			{
				CPrintToChat(client, "%t", "SQL26", g_szChatPrefix, stage, mapname);
			}
		}
		else
		{
			CPrintToChat(client, "%t", "SQL26", g_szChatPrefix, stage, mapname);
		}

		Format(title, 256, "[Top 50 | Stage %i | %s] \n    Rank    Time               Player", stage, szMap);
		SetMenuTitle(menu, title);
		SetMenuOptionFlags(menu, MENUFLAG_BUTTON_EXIT);
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
		delete stringArray;
	}
}

public int StageTopMenuHandler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		GetMenuItem(menu, item, info, sizeof(info));
		g_MenuLevel[client] = 3;
		db_viewPlayerProfile(client, g_ProfileStyleSelect[client], info, true, "");
	}
	else if (action == MenuAction_Cancel)
	{
		db_viewWrcpMap(client, g_szWrcpMapSelect[client]);
	}
	else if (action == MenuAction_End)
		delete menu;
}

public void db_viewStageRecords()
{
	char szQuery[512];
	Format(szQuery, sizeof(szQuery), sql_selectMapWrcp, g_szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewStageRecords - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_viewStageRecordsCallback, szQuery, _, DBPrio_Low);
}

public void sql_viewStageRecordsCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[Surftimer] SQL Error (sql_viewStageRecordsCallback): %s", error);
		if (!g_bServerDataLoaded)
		{
			db_selectTotalBonusCount();
			return;
		}
	}

	if (results.HasResults)
	{
		int stage;
		int style;
		char szName[MAX_NAME_LENGTH];

		while (results.FetchRow())
		{
			results.FetchString(0, szName, sizeof(szName));
			stage = results.FetchInt(2);
			style = results.FetchInt(3);

			if (style == 0)
			{
				g_fStageRecord[stage] = results.FetchFloat(1);

				g_iWrcpVelsStartServerRecord[stage][0] = results.FetchInt(4);
				g_iWrcpVelsStartServerRecord[stage][1] = results.FetchInt(5);
				g_iWrcpVelsStartServerRecord[stage][2] = results.FetchInt(6);
				g_iWrcpVelsEndServerRecord[stage][0] = results.FetchInt(7);
				g_iWrcpVelsEndServerRecord[stage][1] = results.FetchInt(8);
				g_iWrcpVelsEndServerRecord[stage][2] = results.FetchInt(9);

				if (g_fStageRecord[stage] > -1.0 && !results.IsFieldNull(1))
				{
					g_fStageRecord[stage] = results.FetchFloat(1);
					Format(g_szStageRecordPlayer[stage], sizeof(g_szStageRecordPlayer), szName);
					FormatTimeFloat(0, g_fStageRecord[stage], 3, g_szRecordStageTime[stage], 64);
				}
				else
				{
					Format(g_szStageRecordPlayer[stage], sizeof(g_szStageRecordPlayer), "N/A");
					Format(g_szRecordStageTime[stage], 64, "N/A");
					g_fStageRecord[stage] = 9999999.0;
				}
			}
			else
			{
				g_fStyleStageRecord[style][stage] = results.FetchFloat(1);
				if (g_fStyleStageRecord[style][stage] > -1.0 && !results.IsFieldNull(1))
				{
					g_fStyleStageRecord[style][stage] = results.FetchFloat(1);
					FormatTimeFloat(0, g_fStyleStageRecord[style][stage], 3, g_szStyleRecordStageTime[style][stage], 64);
				}
				else
				{
					Format(g_szStyleRecordStageTime[style][stage], 64, "N/A");
					g_fStyleStageRecord[style][stage] = 9999999.0;
				}
			}
		}
	}
	else
	{
		for (int i = 1; i <= g_TotalStages; i++)
		{
			Format(g_szRecordStageTime[i], 64, "N/A");
			g_fStageRecord[i] = 9999999.0;
			g_iWrcpVelsStartServerRecord[i][0] = 0;
			g_iWrcpVelsStartServerRecord[i][1] = 0;
			g_iWrcpVelsStartServerRecord[i][2] = 0;
			g_iWrcpVelsEndServerRecord[i][0] = 0;
			g_iWrcpVelsEndServerRecord[i][1] = 0;
			g_iWrcpVelsEndServerRecord[i][2] = 0;
			
			for (int s = 1; s < MAX_STYLES; s++)
			{
				Format(g_szStyleRecordStageTime[s][i], 64, "N/A");
				g_fStyleStageRecord[s][i] = 9999999.0;
			}
		}
	}

	if (!g_bServerDataLoaded)
		db_viewTotalStageRecords();
}

public void db_viewTotalStageRecords()
{
	char szQuery[512];
	Format(szQuery, sizeof(szQuery), "SELECT stage, style, count(1) FROM ck_wrcps WHERE mapname = '%s' GROUP BY stage, style;", g_szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewTotalStageRecords - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_viewTotalStageRecordsCallback, szQuery, _, DBPrio_Low);
}

public void sql_viewTotalStageRecordsCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_viewTotalStageRecordsCallback): %s", error);
		if (!g_bServerDataLoaded)
			db_selectTotalBonusCount();
		return;
	}

	if (results.HasResults)
	{
		int stage;
		int style;

		for (int i = 0; i < CPLIMIT; i++)
		{
			g_TotalStageRecords[i] = 0;
		}

		while (results.FetchRow())
		{
			stage = results.FetchInt(0);
			style = results.FetchInt(1);

			if (style == 0)
			{
				g_TotalStageRecords[stage] = results.FetchInt(2);
				if (g_TotalStageRecords[stage] > -1.0 && !results.IsFieldNull(2))
				{
					g_TotalStageRecords[stage] = results.FetchInt(2);
				}
				else
				{
					g_TotalStageRecords[stage] = 0;
				}
			}
			else
			{
				g_TotalStageStyleRecords[style][stage] = results.FetchInt(2);
				if (g_TotalStageStyleRecords[style][stage] > -1.0 && !results.IsFieldNull(2))
				{
					g_TotalStageStyleRecords[style][stage] = results.FetchInt(2);
				}
				else
				{
					g_TotalStageStyleRecords[style][stage] = 0;
				}
			}
		}
	}
	else
	{
		for (int i = 1; i <= g_TotalStages; i++)
		{
			g_TotalStageRecords[i] = 0;
			for (int s = 1; i < MAX_STYLES; s++)
			{
				g_TotalStageStyleRecords[s][i] = 0;
			}
		}
	}

	if (!g_bServerDataLoaded)
		db_selectTotalBonusCount();
}

// Styles for maps
public void db_selectStyleRecord(int client, int style)
{
	if (!IsValidClient(client))
	return;

	Handle stylepack = CreateDataPack();
	WritePackCell(stylepack, GetClientUserId(client));
	WritePackCell(stylepack, style);

	char szQuery[255];
	Format(szQuery, sizeof(szQuery), "SELECT runtimepro FROM `ck_playertimes` WHERE `steamid` = '%s' AND `mapname` = '%s' AND `style` = %i AND `runtimepro` > -1.0", g_szSteamID[client], g_szMapName, style);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectStyleRecord - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_selectStyleRecordCallback, szQuery, stylepack, DBPrio_Low);
}

public void sql_selectStyleRecordCallback(Database db, DBResultSet results, const char[] error, DataPack stylepack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_selectStyleRecordCallback): %s", error);
		delete stylepack;
		return;
	}

	ResetPack(stylepack);
	int client = GetClientOfUserId(ReadPackCell(stylepack));
	int style = ReadPackCell(stylepack);
	delete stylepack;

	if (!IsValidClient(client))
	{
		return;
	}


	char szQuery[512];

	// Found old time from database
	if (results.HasResults && results.FetchRow())
	{
		float time = results.FetchFloat(0);

		// If old time was slower than the new time, update record
		if ((g_fFinalTime[client] <= time || time <= 0.0))
		{
			db_updateStyleRecord(client, style);
		}
	}
	else
	{ // No record found from database - Let's insert

	// Escape name for SQL injection protection
	char szName[MAX_NAME_LENGTH * 2 + 1], szUName[MAX_NAME_LENGTH];
	GetClientName(client, szUName, MAX_NAME_LENGTH);
	g_dDb.Escape(szUName, szName, MAX_NAME_LENGTH);

	// Move required information in datapack
	Handle pack = CreateDataPack();
	WritePackFloat(pack, g_fFinalTime[client]);
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, style);

	g_StyleMapTimesCount[style]++;

	Format(szQuery, sizeof(szQuery), "INSERT INTO ck_playertimes (steamid, mapname, name, runtimepro, style) VALUES ('%s', '%s', '%s', '%f', %i)", g_szSteamID[client], g_szMapName, szName, g_fFinalTime[client], style);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "sql_selectStyleRecordCallback - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_UpdateStyleRecordCallback, szQuery, pack, DBPrio_Low);
}
}

// If latest record was faster than old - Update time
public void db_updateStyleRecord(int client, int style)
{
	char szUName[MAX_NAME_LENGTH];

	if (IsValidClient(client))
	GetClientName(client, szUName, MAX_NAME_LENGTH);
	else
	return;

	// Also updating name in database, escape string
	char szName[MAX_NAME_LENGTH * 2 + 1];
	g_dDb.Escape(szUName, szName, MAX_NAME_LENGTH * 2 + 1);

	// Packing required information for later
	Handle pack = CreateDataPack();
	WritePackFloat(pack, g_fFinalTime[client]);
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, style);

	char szQuery[1024];
	// "UPDATE ck_playertimes SET name = '%s', runtimepro = '%f' WHERE steamid = '%s' AND mapname = '%s';";
	Format(szQuery, sizeof(szQuery), "UPDATE `ck_playertimes` SET `name` = '%s', runtimepro = '%f' WHERE `steamid` = '%s' AND `mapname` = '%s' AND `style` = %i;", szName, g_fFinalTime[client], g_szSteamID[client], g_szMapName, style);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_updateStyleRecord - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_UpdateStyleRecordCallback, szQuery, pack, DBPrio_Low);
}

public void SQL_UpdateStyleRecordCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_UpdateStyleRecordCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	float time = ReadPackFloat(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int style = ReadPackCell(pack);
	delete pack;

	if (IsValidClient(client))
	{
		pack = CreateDataPack();
		WritePackCell(pack, GetClientUserId(client));
		WritePackCell(pack, style);

		// Find out how many times are are faster than the players time
		char szQuery[512];
		Format(szQuery, sizeof(szQuery), "SELECT count(runtimepro) FROM `ck_playertimes` WHERE `mapname` = '%s' AND `style` = %i AND `runtimepro` < %f-(1E-3);", g_szMapName, style, time);
		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "SQL_UpdateStyleRecordCallback - szQuery: %s", szQuery);
		}
		g_dDb.Query(SQL_UpdateStyleRecordCallback2, szQuery, pack, DBPrio_Low);
	}
}

public void SQL_UpdateStyleRecordCallback2(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_UpdateStyleRecordProCallback2): %s", error);
		delete pack;
		return;
	}
	// Get players rank, 9999999 = error
	int rank = 9999999;
	if (results.HasResults && results.FetchRow())
	{
		rank = (results.FetchInt(0)+1);
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int style = ReadPackCell(pack);
	delete pack;

	if (IsValidClient(client))
	{
		g_StyleMapRank[style][client] = rank;
		StyleFinishedMsgs(client, style);
	}
}

public void db_viewStyleMapRank(int client, int style)
{
	char szQuery[512];
	if (!IsValidClient(client))
	return;

	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, style);

	Format(szQuery, sizeof(szQuery), "SELECT COUNT(*) FROM ck_playertimes WHERE runtimepro <= (SELECT runtimepro FROM ck_playertimes WHERE steamid = '%s' AND mapname = '%s' AND style = %i AND runtimepro > -1.0) AND mapname = '%s' AND style = %i AND runtimepro > -1.0;", g_szSteamID[client], g_szMapName, style, g_szMapName, style);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewStyleMapRank - szQuery: %s", szQuery);
	}
	g_dDb.Query(db_viewStyleMapRankCallback, szQuery, pack, DBPrio_Low);
}

public void db_viewStyleMapRankCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_viewStyleMapRankCallback): %s ", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int style = ReadPackCell(pack);
	delete pack;

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			g_StyleMapRank[style][client] = results.FetchInt(0);
		}
	}

	return;
}

public void db_selectStyleMapTopSurfers(int client, char mapname[128], int style)
{
	char szQuery[1024];
	Format(szQuery, sizeof(szQuery), "SELECT db2.steamid, db1.name, db2.runtimepro as overall, db1.steamid, db2.mapname FROM ck_playertimes as db2 INNER JOIN ck_playerrank as db1 on db2.steamid = db1.steamid WHERE db2.mapname LIKE '%c%s%c' AND db2.style = %i AND db2.runtimepro > -1.0 ORDER BY overall ASC LIMIT 100;", PERCENT, mapname, PERCENT, style);
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackString(pack, mapname);
	WritePackCell(pack, style);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectStyleMapTopSurfers - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_selectTopSurfersCallback, szQuery, pack, DBPrio_Low);
}

// Styles for bonuses
public void db_insertBonusStyle(int client, char szSteamId[32], char szUName[128], float FinalTime, int zoneGrp, int style)
{
	char szQuery[1024];
	char szName[MAX_NAME_LENGTH * 2 + 1];
	g_dDb.Escape(szUName, szName, MAX_NAME_LENGTH * 2 + 1);
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, zoneGrp);
	WritePackCell(pack, style);
	Format(szQuery, sizeof(szQuery), "INSERT INTO ck_bonus (steamid, name, mapname, runtime, zonegroup, style) VALUES ('%s', '%s', '%s', '%f', '%i', '%i')", szSteamId, szName, g_szMapName, FinalTime, zoneGrp, style);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_insertBonusStyle - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_insertBonusStyleCallback, szQuery, pack, DBPrio_Low);
}

public void SQL_insertBonusStyleCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_insertBonusStyleCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int zgroup = ReadPackCell(pack);
	int style = ReadPackCell(pack);
	delete pack;

	if (IsValidClient(client))
	{
		db_viewMapRankBonusStyle(client, zgroup, 1, style);
	}
}

public void db_viewMapRankBonusStyle(int client, int zgroup, int type, int style)
{
	char szQuery[1024];
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, zgroup);
	WritePackCell(pack, type);
	WritePackCell(pack, style);

	Format(szQuery, sizeof(szQuery), "SELECT name FROM ck_bonus WHERE runtime <= (SELECT runtime FROM ck_bonus WHERE steamid = '%s' AND mapname= '%s' AND style = %i AND runtime > 0.0 AND zonegroup = %i) AND mapname = '%s' AND style = %i AND zonegroup = %i;", g_szSteamID[client], g_szMapName, style, zgroup, g_szMapName, style, zgroup);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewMapRankBonusStyle - szQuery: %s", szQuery);
	}
	g_dDb.Query(db_viewMapRankBonusStyleCallback, szQuery, pack, DBPrio_Low);
}

public void db_viewMapRankBonusStyleCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_viewMapRankBonusStyleCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int zgroup = ReadPackCell(pack);
	int type = ReadPackCell(pack);
	int style = ReadPackCell(pack);
	delete pack;

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			g_StyleMapRankBonus[style][zgroup][client] = results.RowCount;
		}
		else
		{
			g_StyleMapRankBonus[style][zgroup][client] = 9999999;
		}

		switch (type)
		{
			case 1: 
			{
				g_iStyleBonusCount[style][zgroup]++;
				PrintChatBonusStyle(client, zgroup, style);
			}
			case 2: 
			{
				PrintChatBonusStyle(client, zgroup, style);
			}
		}
	}
}

public void db_updateBonusStyle(int client, char szSteamId[32], char szUName[128], float FinalTime, int zoneGrp, int style)
{
	char szQuery[1024];
	char szName[MAX_NAME_LENGTH * 2 + 1];
	Handle datapack = CreateDataPack();
	WritePackCell(datapack, GetClientUserId(client));
	WritePackCell(datapack, zoneGrp);
	WritePackCell(datapack, style);
	g_dDb.Escape(szUName, szName, MAX_NAME_LENGTH * 2 + 1);
	Format(szQuery, sizeof(szQuery), "UPDATE ck_bonus SET runtime = '%f', name = '%s' WHERE steamid = '%s' AND mapname = '%s' AND zonegroup = %i AND style = %i", FinalTime, szName, szSteamId, g_szMapName, zoneGrp, style);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_updateBonusStyle - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_updateBonusStyleCallback, szQuery, datapack, DBPrio_Low);
}


public void SQL_updateBonusStyleCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (SQL_updateBonusStyleCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int zgroup = ReadPackCell(pack);
	int style = ReadPackCell(pack);
	delete pack;

	if (IsValidClient(client))
	{
		db_viewMapRankBonusStyle(client, zgroup, 2, style);
	}
}

public void db_currentBonusStyleRunRank(int client, int zGroup, int style)
{
	char szQuery[512];
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, zGroup);
	WritePackCell(pack, style);
	Format(szQuery, sizeof(szQuery), "SELECT count(runtime)+1 FROM ck_bonus WHERE mapname = '%s' AND zonegroup = '%i' AND style = '%i' AND runtime < %f", g_szMapName, zGroup, style, g_fFinalTime[client]);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_currentBonusStyleRunRank - szQuery: %s", szQuery);
	}
	g_dDb.Query(db_viewBonusStyleRunRank, szQuery, pack, DBPrio_Low);
}

public void db_viewBonusStyleRunRank(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_viewBonusStyleRunRank): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int zGroup = ReadPackCell(pack);
	int style = ReadPackCell(pack);
	delete pack;

	if (IsValidClient(client))
	{
		int rank;
		if (results.HasResults && results.FetchRow())
		{
			rank = results.FetchInt(0);
		}

		PrintChatBonusStyle(client, zGroup, style, rank);
	}
}

// Style WRCPS
public void db_viewStyleStageRanks(int client, int stage, int style)
{
	char szQuery[512];
	if (!IsValidClient(client))
	return;

	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, stage);
	WritePackCell(pack, style);

	Format(szQuery, sizeof(szQuery), "SELECT COUNT(*) FROM ck_wrcps WHERE runtimepro <= (SELECT runtimepro FROM ck_wrcps WHERE steamid = '%s' AND mapname = '%s' AND stage = %i AND style = %i AND runtimepro > -1.0) AND mapname = '%s' AND stage = %i AND style = %i AND runtimepro > -1.0;", g_szSteamID[client], g_szMapName, stage, style, g_szMapName, stage, style);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewStyleStageRanks - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_viewStyleStageRanksCallback, szQuery, pack, DBPrio_Low);
}

public void sql_viewStyleStageRanksCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_viewStyleStageRanksCallback): %s ", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int stage = ReadPackCell(pack);
	int style = ReadPackCell(pack);
	delete pack;

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			g_StyleStageRank[style][client][stage] = results.FetchInt(0);
		}
	}
}

public void db_viewWrcpStyleMapRecord(int client, int style)
{
	char szQuery[1024];
	Format(szQuery, sizeof(szQuery), "SELECT name, s%s FROM `ck_wrcps` WHERE `mapname` = '%s' AND `style` = %i AND `s%s` > -1.0 ORDER BY s%s ASC LIMIT 0, 1", g_szWrcpMapSelect[client], g_szMapName, style, g_szWrcpMapSelect[client], g_szWrcpMapSelect[client]);

	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, style);

	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewWrcpStyleMapRecord - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_viewWrcpStyleMapRecordCallback, szQuery, pack, DBPrio_Low);
}

public void sql_viewWrcpStyleMapRecordCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_viewWrcpStyleMapRecordCallback): %s ", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int style = ReadPackCell(pack);
	delete pack;

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			char szName[MAX_NAME_LENGTH];
			float runtimepro;
			char szRuntimepro[64];

			results.FetchString(0, szName, 128);
			runtimepro = results.FetchFloat(1);
			FormatTimeFloat(0, runtimepro, 3, szRuntimepro, 64);

			CPrintToChat(client, "%t", "SQL27", g_szChatPrefix, szName, g_szStyleRecordPrint[style], szRuntimepro, g_szWrcpMapSelect[client], g_szMapName);
			return;
		}
		else
		{
			CPrintToChat(client, "%t", "SQL24", g_szChatPrefix);
		}
	}
}

public void db_viewStyleWrcpMap(int client, char mapname[128], int style)
{
	char szQuery[1024];
	Format(szQuery, sizeof(szQuery), "SELECT `mapname`, COUNT(`zonetype`) AS stages FROM `ck_zones` WHERE `zonetype` = '3' AND `mapname` = (SELECT DISTINCT `mapname` FROM `ck_zones` WHERE `zonetype` = '3' AND `mapname` LIKE '%c%s%c' LIMIT 0, 1)", PERCENT, g_szWrcpMapSelect[client], PERCENT);
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, style);
	WritePackString(pack, mapname);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewStyleWrcpMap - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_viewStyleWrcpMapCallback, szQuery, pack, DBPrio_Low);
}

public void sql_viewStyleWrcpMapCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_viewStyleWrcpMapCallback): %s ", error);
		delete pack;
		return;
	}

	int totalstages;
	char mapnameresult[128];
	char stage[MAXPLAYERS + 1];
	char szStageString[MAXPLAYERS + 1];
	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int style = ReadPackCell(pack);
	char mapname[128];
	ReadPackString(pack, mapname, 128);
	delete pack;

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			totalstages = results.FetchInt(1) + 1;
			results.FetchString(0, mapnameresult, 128);
			if (totalstages == 0 || totalstages == 1)
			{
				CPrintToChat(client, "%t", "SQL23", g_szChatPrefix, mapname);
				return;
			}

			if (pack != INVALID_HANDLE)
			{
				g_StyleStageSelect[client] = style;
				g_szWrcpMapSelect[client] = mapnameresult;
				Menu menu;
				menu = CreateMenu(StageStyleSelectMenuHandler);

				SetMenuTitle(menu, "%s: select a stage [%s]\n------------------------------\n", mapnameresult, g_szStyleMenuPrint[style]);
				int stageCount = totalstages;
				for (int i = 1; i <= stageCount; i++)
				{
					stage[0] = i;
					Format(szStageString, sizeof(szStageString), "Stage %i", i);
					AddMenuItem(menu, stage[0], szStageString);
				}
				g_bSelectWrcp[client] = true;
				SetMenuOptionFlags(menu, MENUFLAG_BUTTON_EXIT);
				DisplayMenu(menu, client, MENU_TIME_FOREVER);
			}
		}
	}
}

public void db_selectStageStyleTopSurfers(int client, char info[32], char mapname[128], int style)
{
	char szQuery[1024];
	Format(szQuery, sizeof(szQuery), "SELECT db2.steamid, db1.name, db2.runtimepro as overall, db1.steamid, db2.mapname FROM ck_wrcps as db2 INNER JOIN ck_playerrank as db1 on db2.steamid = db1.steamid WHERE db2.mapname = '%s' AND db2.style = %i AND db2.stage = %i AND db2.runtimepro > -1.0 ORDER BY overall ASC LIMIT 50;", mapname, style, info);
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, style);
	// WritePackCell(pack, stage);
	WritePackString(pack, info);
	WritePackString(pack, mapname);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectStageStyleTopSurfers - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_selectStageStyleTopSurfersCallback, szQuery, pack, DBPrio_Low);
}

public void sql_selectStageStyleTopSurfersCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_selectStageStyleTopSurfersCallback): %s ", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int style = ReadPackCell(pack);
	char stage[32];
	ReadPackString(pack, stage, 32);
	char mapname[128];
	ReadPackString(pack, mapname, 128);
	delete pack;

	if (IsValidClient(client))
	{
		char szSteamID[32];
		char szName[64];
		float time;
		char szMap[128];
		char szValue[128];
		char lineBuf[256];
		Handle stringArray = CreateArray(100);
		Handle menu;
		menu = CreateMenu(StageStyleTopMenuHandler);
		SetMenuPagination(menu, 5);
		bool bduplicat = false;
		char title[256];
		if (results.HasResults)
		{
			int i = 1;
			while (results.FetchRow())
			{
				bduplicat = false;
				results.FetchString(0, szSteamID, 32);
				results.FetchString(1, szName, 64);
				time = results.FetchFloat(2);
				results.FetchString(4, szMap, 128);
				if (i == 1 || (i > 1))
				{
					int stringArraySize = GetArraySize(stringArray);
					for (int x = 0; x < stringArraySize; x++)
					{
						GetArrayString(stringArray, x, lineBuf, sizeof(lineBuf));
						if (StrEqual(lineBuf, szName, false))
							bduplicat = true;
					}
					if (bduplicat == false && i < 51)
					{
						char szTime[32];
						FormatTimeFloat(client, time, 3, szTime, sizeof(szTime));
						if (time < 3600.0)
						Format(szTime, 32, "   %s", szTime);
						if (i == 100)
						Format(szValue, 128, "[%i.] %s |    » %s", i, szTime, szName);
						if (i >= 10)
						Format(szValue, 128, "[%i.] %s |    » %s", i, szTime, szName);
						else
						Format(szValue, 128, "[0%i.] %s |    » %s", i, szTime, szName);
						AddMenuItem(menu, szSteamID, szValue, ITEMDRAW_DEFAULT);
						PushArrayString(stringArray, szName);
						i++;
					}
				}
			}
			if (i == 1)
			{
				CPrintToChat(client, "%t", "SQL26", g_szChatPrefix, stage, mapname);
			}
		}
		else
		{
			CPrintToChat(client, "%t", "SQL26", g_szChatPrefix, stage, mapname);
		}

		Format(title, 256, "[Top 50 %s | Stage %i | %s] \n    Rank    Time               Player", g_szStyleMenuPrint[style], stage, szMap);
		SetMenuTitle(menu, title);
		SetMenuOptionFlags(menu, MENUFLAG_BUTTON_EXIT);
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
		delete stringArray;
	}
}

public int StageStyleTopMenuHandler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		GetMenuItem(menu, item, info, sizeof(info));
		g_MenuLevel[client] = 3;
		db_viewPlayerProfile(client, g_ProfileStyleSelect[client], info, true, "");
	}
	else if (action == MenuAction_Cancel)
	{
			db_viewStyleWrcpMap(client, g_szWrcpMapSelect[client], g_iWrcpMenuStyleSelect[client]);
	}
	else if (action == MenuAction_End)
		delete menu;
}

public void db_selectMapRank(int client, char szSteamId[32], char szMapName[128])
{
	char szQuery[1024];
	if (StrEqual(szMapName, "surf_me"))
			Format(szQuery, sizeof(szQuery), "SELECT `steamid`, `name`, `mapname`, `runtimepro` FROM `ck_playertimes` WHERE `steamid` = '%s' AND `mapname` = '%s' AND style = 0 LIMIT 1;", szSteamId, szMapName);
	else
		Format(szQuery, sizeof(szQuery), "SELECT `steamid`, `name`, `mapname`, `runtimepro` FROM `ck_playertimes` WHERE `steamid` = '%s' AND `mapname` LIKE '%c%s%c' AND style = 0 LIMIT 1;", szSteamId, PERCENT, szMapName, PERCENT);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectMapRank - szQuery: %s", szQuery);
	}
	g_dDb.Query(db_selectMapRankCallback, szQuery, GetClientUserId(client), DBPrio_Low);
}

public void db_selectMapRankCallback(Database db, DBResultSet results, const char[] error, any userid)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[Surftimer] SQL Error (db_selectMapRankCallback): %s", error);
		return;
	}

	int client = GetClientOfUserId(userid);

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			char szSteamId[32];
			char playername[MAX_NAME_LENGTH];
			char mapname[128];
			float runtimepro;

			results.FetchString(0, szSteamId, 32);
			results.FetchString(1, playername, MAX_NAME_LENGTH);
			results.FetchString(2, mapname, sizeof(mapname));
			runtimepro = results.FetchFloat(3);

			FormatTimeFloat(client, runtimepro, 3, g_szRuntimepro[client], sizeof(g_szRuntimepro));

			Handle pack = CreateDataPack();
			WritePackCell(pack, GetClientUserId(client));
			WritePackString(pack, szSteamId);
			WritePackString(pack, playername);
			WritePackString(pack, mapname);

			char szQuery[1024];

			Format(szQuery, sizeof(szQuery), "SELECT count(name) FROM `ck_playertimes` WHERE `mapname` = '%s' AND style = 0;", mapname);
			if (g_cLogQueries.BoolValue)
			{
				LogToFile(g_szQueryFile, "db_selectMapRankCallback - szQuery: %s", szQuery);
			}
			g_dDb.Query(db_SelectTotalMapCompletesCallback, szQuery, pack, DBPrio_Low);
		}
		else
		{
			CPrintToChat(client, "%t", "SQL28", g_szChatPrefix);
		}
	}
}

public void db_SelectTotalMapCompletesCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_SelectTotalMapCompletesCallback): %s ", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	char szSteamId[32];
	char playername[MAX_NAME_LENGTH];
	char mapname[128];
	ReadPackString(pack, szSteamId, 32);
	ReadPackString(pack, playername, sizeof(playername));
	ReadPackString(pack, mapname, sizeof(mapname));

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			g_totalPlayerTimes[client] = results.FetchInt(0);

			char szQuery[1024];

			Format(szQuery, sizeof(szQuery), "SELECT COUNT(name),mapname FROM ck_playertimes WHERE runtimepro <= (SELECT runtimepro FROM ck_playertimes WHERE steamid = '%s' AND mapname = '%s' AND runtimepro > -1.0 AND style = 0) AND mapname = '%s' AND style = 0 AND runtimepro > -1.0;", szSteamId, mapname, mapname);
			if (g_cLogQueries.BoolValue)
			{
				LogToFile(g_szQueryFile, "db_SelectTotalMapCompletesCallback - szQuery: %s", szQuery);
			}
			g_dDb.Query(db_SelectPlayersMapRankCallback, szQuery, pack, DBPrio_Low);
			return;
		}
	}

	delete pack;
}

public void db_SelectPlayersMapRankCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_SelectPlayersMapRankCallback): %s ", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = ReadPackCell(pack);
	char szSteamId[32];
	char playername[MAX_NAME_LENGTH];
	char mapname[128];
	ReadPackString(pack, szSteamId, 32);
	ReadPackString(pack, playername, sizeof(playername));
	ReadPackString(pack, mapname, sizeof(mapname));
	delete pack;

	if (results.HasResults && results.FetchRow())
	{
		int rank;

		rank = results.FetchInt(0);

		if (StrEqual(mapname, g_szMapName))
		{
			char szGroup[128];
			if (rank >= 11 && rank <= g_G1Top)
				Format(szGroup, 128, "[%cGroup 1%c]", DARKRED, WHITE);
			else if (rank >= g_G2Bot && rank <= g_G2Top)
				Format(szGroup, 128, "[%cGroup 2%c]", GREEN, WHITE);
			else if (rank >= g_G3Bot && rank <= g_G3Top)
				Format(szGroup, 128, "[%cGroup 3%c]", BLUE, WHITE);
			else if (rank >= g_G4Bot && rank <= g_G4Top)
				Format(szGroup, 128, "[%cGroup 4%c]", YELLOW, WHITE);
			else if (rank >= g_G5Bot && rank <= g_G5Top)
				Format(szGroup, 128, "[%cGroup 5%c]", GRAY, WHITE);
			else
				Format(szGroup, 128, "");

			if (rank >= 11 && rank <= g_G5Top)
				CPrintToChatAll("%t", "SQL29", g_szChatPrefix, playername, rank, g_totalPlayerTimes[client], szGroup, g_szRuntimepro[client], mapname);
			else
				CPrintToChatAll("%t", "SQL30", g_szChatPrefix, playername, rank, g_totalPlayerTimes[client], g_szRuntimepro[client], mapname);
		}
		else
		{
			CPrintToChatAll("%t", "SQL31", g_szChatPrefix, playername, rank, g_totalPlayerTimes[client], g_szRuntimepro[client], mapname);
		}
	}
}

// sm_mrank @x command
public void db_selectMapRankUnknown(int client, char szMapName[128], int rank)
{
	char szQuery[1024];
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, rank);

	rank = rank - 1;
	Format(szQuery, sizeof(szQuery), "SELECT `steamid`, `name`, `mapname`, `runtimepro` FROM `ck_playertimes` WHERE `mapname` LIKE '%c%s%c' AND style = 0 ORDER BY `runtimepro` ASC LIMIT %i, 1;", PERCENT, szMapName, PERCENT, rank);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectMapRankUnknown - szQuery: %s", szQuery);
	}
	g_dDb.Query(db_selectMapRankUnknownCallback, szQuery, pack, DBPrio_Low);
}

public void db_selectMapRankUnknownCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_selectMapRankUnknownCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int rank = ReadPackCell(pack);
	delete pack;

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			char szSteamId[32];
			char playername[MAX_NAME_LENGTH];
			char mapname[128];
			float runtimepro;

			results.FetchString(0, szSteamId, 32);
			results.FetchString(1, playername, MAX_NAME_LENGTH);
			results.FetchString(2, mapname, sizeof(mapname));
			runtimepro = results.FetchFloat(3);

			FormatTimeFloat(client, runtimepro, 3, g_szRuntimepro[client], sizeof(g_szRuntimepro));

			pack = CreateDataPack();
			WritePackCell(pack, GetClientUserId(client));
			WritePackCell(pack, rank);
			WritePackString(pack, szSteamId);
			WritePackString(pack, playername);
			WritePackString(pack, mapname);

			char szQuery[1024];

			Format(szQuery, sizeof(szQuery), "SELECT count(name) FROM `ck_playertimes` WHERE `mapname` = '%s' AND style = 0;", mapname);
			if (g_cLogQueries.BoolValue)
			{
				LogToFile(g_szQueryFile, "db_selectMapRankUnknownCallback - szQuery: %s", szQuery);
			}
			g_dDb.Query(db_SelectTotalMapCompletesUnknownCallback, szQuery, pack, DBPrio_Low);
		}
		else
		{
			CPrintToChat(client, "%t", "SQL28", g_szChatPrefix);
		}
	}
}

public void db_SelectTotalMapCompletesUnknownCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_SelectTotalMapCompletesUnknownCallback): %s ", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int rank = ReadPackCell(pack);
	char szSteamId[32];
	char playername[MAX_NAME_LENGTH];
	char mapname[128];
	ReadPackString(pack, szSteamId, 32);
	ReadPackString(pack, playername, sizeof(playername));
	ReadPackString(pack, mapname, sizeof(mapname));
	delete pack;

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			int totalplayers = results.FetchInt(0);

			if (StrEqual(mapname, g_szMapName))
			{
				char szGroup[128];
				if (rank >= 11 && rank <= g_G1Top)
					Format(szGroup, 128, "[%cGroup 1%c]", DARKRED, WHITE);
				else if (rank >= g_G2Bot && rank <= g_G2Top)
					Format(szGroup, 128, "[%cGroup 2%c]", GREEN, WHITE);
				else if (rank >= g_G3Bot && rank <= g_G3Top)
					Format(szGroup, 128, "[%cGroup 3%c]", BLUE, WHITE);
				else if (rank >= g_G4Bot && rank <= g_G4Top)
					Format(szGroup, 128, "[%cGroup 4%c]", YELLOW, WHITE);
				else if (rank >= g_G5Bot && rank <= g_G5Top)
					Format(szGroup, 128, "[%cGroup 5%c]", GRAY, WHITE);
				else
					Format(szGroup, 128, "");

				if (rank >= 11 && rank <= g_G5Top)
					CPrintToChatAll("%t", "SQL33", g_szChatPrefix, playername, rank, totalplayers, szGroup, g_szRuntimepro[client], mapname);
				else
					CPrintToChatAll("%t", "SQL34", g_szChatPrefix, playername, rank, totalplayers, g_szRuntimepro[client], mapname);
			}
			else
			{
				CPrintToChatAll("%t", "SQL35", g_szChatPrefix, playername, rank, totalplayers, g_szRuntimepro[client], mapname);
			}
		}
		else
		{
			CPrintToChat(client, "%t", "SQL28", g_szChatPrefix);
		}
	}
}

public void db_selectBonusRank(int client, char szSteamId[32], char szMapName[128], int bonus)
{
	char szQuery[1024];
	Format(szQuery, sizeof(szQuery), "SELECT `steamid`, `name`, `mapname`, `runtime`, zonegroup FROM `ck_bonus` WHERE `steamid` = '%s' AND `mapname` LIKE '%c%s%c' AND zonegroup = %i AND style = 0 LIMIT 1;", szSteamId, PERCENT, szMapName, PERCENT, bonus);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectBonusRank - szQuery: %s", szQuery);
	}
	g_dDb.Query(db_selectBonusRankCallback, szQuery, GetClientUserId(client), DBPrio_Low);
}

public void db_selectBonusRankCallback(Database db, DBResultSet results, const char[] error, any userid)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_selectBonusRankCallback): %s", error);
		return;
	}

	int client = GetClientOfUserId(userid);

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			char szSteamId[32];
			char playername[MAX_NAME_LENGTH];
			char mapname[128];
			float runtimepro;
			int bonus;

			results.FetchString(0, szSteamId, 32);
			results.FetchString(1, playername, MAX_NAME_LENGTH);
			results.FetchString(2, mapname, sizeof(mapname));
			runtimepro = results.FetchFloat(3);
			bonus = results.FetchInt(4);

			FormatTimeFloat(client, runtimepro, 3, g_szRuntimepro[client], sizeof(g_szRuntimepro));

			Handle pack = CreateDataPack();
			WritePackCell(pack, GetClientUserId(client));
			WritePackString(pack, szSteamId);
			WritePackString(pack, playername);
			WritePackString(pack, mapname);
			WritePackCell(pack, bonus);

			char szQuery[1024];

			Format(szQuery, sizeof(szQuery), "SELECT count(name) FROM `ck_bonus` WHERE `mapname` = '%s' AND zonegroup = %i AND style = 0 AND runtime > 0.0;", mapname, bonus);
			if (g_cLogQueries.BoolValue)
			{
				LogToFile(g_szQueryFile, "db_selectBonusRankCallback - szQuery: %s", szQuery);
			}
			g_dDb.Query(db_SelectTotalBonusCompletesCallback, szQuery, pack, DBPrio_Low);
		}
		else
		{
			CPrintToChat(client, "%t", "SQL28", g_szChatPrefix);
		}
	}
}

public void db_SelectTotalBonusCompletesCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_SelectTotalBonusCompletesCallback): %s ", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	char szSteamId[32];
	char playername[MAX_NAME_LENGTH];
	char mapname[128];
	ReadPackString(pack, szSteamId, 32);
	ReadPackString(pack, playername, sizeof(playername));
	ReadPackString(pack, mapname, sizeof(mapname));
	int bonus = ReadPackCell(pack);

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			g_totalPlayerTimes[client] = results.FetchInt(0);

			char szQuery[1024];

			Format(szQuery, sizeof(szQuery), "SELECT name,mapname FROM ck_bonus WHERE runtime <= (SELECT runtime FROM ck_bonus WHERE steamid = '%s' AND mapname = '%s' AND zonegroup = %i AND style = 0 AND runtime > -1.0) AND mapname = '%s' AND zonegroup = %i AND runtime > -1.0 ORDER BY runtime;", szSteamId, mapname, bonus, mapname, bonus);
			if (g_cLogQueries.BoolValue)
			{
				LogToFile(g_szQueryFile, "db_SelectTotalBonusCompletesCallback - szQuery: %s", szQuery);
			}
			g_dDb.Query(db_SelectPlayersBonusRankCallback, szQuery, pack, DBPrio_Low);
			return;
		}
	}

	delete pack;
}

public void db_SelectPlayersBonusRankCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_SelectPlayersBonusRankCallback): %s ", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = ReadPackCell(pack);
	char szSteamId[32];
	char playername[MAX_NAME_LENGTH];
	char mapname[128];
	ReadPackString(pack, szSteamId, 32);
	ReadPackString(pack, playername, sizeof(playername));
	ReadPackString(pack, mapname, sizeof(mapname));
	int bonus = ReadPackCell(pack);
	delete pack;

	if (results.HasResults && results.FetchRow())
	{
		int rank;
		rank = results.RowCount;

		CPrintToChatAll("%t", "SQL36", g_szChatPrefix, playername, rank, g_totalPlayerTimes[client], g_szRuntimepro[client], bonus, mapname);
	}
}

public void db_selectMapRecordTime(int client, char szMapName[128])
{
	char szQuery[1024];

	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackString(pack, szMapName);

	Format(szQuery, sizeof(szQuery), "SELECT db1.runtimepro, IFNULL(db1.mapname, 'NULL'),  db2.name, db1.steamid FROM ck_playertimes db1 INNER JOIN ck_playerrank db2 ON db1.steamid = db2.steamid WHERE mapname LIKE '%c%s%c' AND runtimepro > -1.0 AND db1.style = 0 AND db2.style = 0 ORDER BY runtimepro ASC LIMIT 1", PERCENT, szMapName, PERCENT);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectMapRecordTime - szQuery: %s", szQuery);
	}
	g_dDb.Query(db_selectMapRecordTimeCallback, szQuery, pack, DBPrio_Low);
}

public void db_selectMapRecordTimeCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_selectMapRecordTimeCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	char szMapNameArg[128];
	ReadPackString(pack, szMapNameArg, sizeof(szMapNameArg));
	delete pack;

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			float runtimepro;
			char szMapName[128];
			char szRecord[64];
			char szName[64];
			runtimepro = results.FetchFloat(0);
			results.FetchString(1, szMapName, sizeof(szMapName));
			results.FetchString(2, szName, sizeof(szName));

			if (StrEqual(szMapName, "NULL"))
			{
				CPrintToChat(client, "%t", "NoMapFound", g_szChatPrefix, szMapNameArg);
			}
			else
			{
				FormatTimeFloat(client, runtimepro, 3, szRecord, sizeof(szRecord));

				CPrintToChat(client, "%t", "SQL38", g_szChatPrefix, szName, szRecord, szMapName);
			}
		}
		else
		{
			CPrintToChat(client, "%t", "NoMapFound", g_szChatPrefix, szMapNameArg);
		}
	}
}

public void db_selectPlayerRank(int client, int rank, char szSteamId[32])
{
	char szQuery[1024];

	if (StrContains(szSteamId, "none", false)!= -1) // Select Rank Number
	{
		g_rankArg[client] = rank;
		rank -= 1;
		Format(szQuery, sizeof(szQuery), "SELECT `name`, `points` FROM `ck_playerrank` ORDER BY `points` DESC LIMIT %i, 1;", rank);
	}
	else if (rank == 0) // Self Rank Cmd
	{
		g_rankArg[client] = -1;
		Format(szQuery, sizeof(szQuery), "SELECT `name`, `points` FROM `ck_playerrank` WHERE `steamid` = '%s';", szSteamId);
	}

	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectPlayerRank - szQuery: %s", szQuery);
	}
	g_dDb.Query(db_selectPlayerRankCallback, szQuery, GetClientUserId(client), DBPrio_Low);
}

public void db_selectPlayerRankCallback(Database db, DBResultSet results, const char[] error, any userid)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_selectPlayerRankCallback): %s", error);
		return;
	}

	int client = GetClientOfUserId(userid);

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			char szName[32];
			int points;
			int rank;

			results.FetchString(0, szName, sizeof(szName));
			points = results.FetchInt(1);

			if (g_rankArg[client] == -1)
			{
				rank = g_PlayerRank[client][0];
				g_rankArg[client] = 1;
			}
			else
				rank = g_rankArg[client];

			CPrintToChatAll("%t", "SQL39", g_szChatPrefix, szName, rank, g_pr_RankedPlayers, points);
		}
		else
			CPrintToChat(client, "%t", "SQLTwo7", g_szChatPrefix);
	}
}

public void db_selectPlayerRankUnknown(int client, char szName[128])
{
	char szQuery[1024];
	char szNameE[MAX_NAME_LENGTH * 2 + 1];
	g_dDb.Escape(szName, szNameE, MAX_NAME_LENGTH * 2 + 1);
	Format(szQuery, sizeof(szQuery), "SELECT `steamid`, `name`, `points` FROM `ck_playerrank` WHERE `name` LIKE '%c%s%c' ORDER BY `points` DESC LIMIT 0, 1;", PERCENT, szNameE, PERCENT);

	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectPlayerRankUnknown - szQuery: %s", szQuery);
	}
	g_dDb.Query(db_selectPlayerRankUnknownCallback, szQuery, GetClientUserId(client), DBPrio_Low);
}

public void db_selectPlayerRankUnknownCallback(Database db, DBResultSet results, const char[] error, any userid)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_selectPlayerRankUnknownCallback): %s", error);
		return;
	}

	int client = GetClientOfUserId(userid);

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			char szSteamId[32];
			char szName[128];
			int points;

			results.FetchString(0, szSteamId, sizeof(szSteamId));
			results.FetchString(1, szName, sizeof(szName));
			points = results.FetchInt(2);

			Handle pack = CreateDataPack();
			WritePackString(pack, szSteamId);
			WritePackString(pack, szName);
			WritePackCell(pack, points);
			WritePackCell(pack, GetClientUserId(client));

			char szQuery[1024];
			// "SELECT name FROM ck_playerrank WHERE points >= (SELECT points FROM ck_playerrank WHERE steamid = '%s') ORDER BY points";
			Format(szQuery, sizeof(szQuery), sql_selectRankedPlayersRank, 0, szSteamId, 0);
			if (g_cLogQueries.BoolValue)
			{
				LogToFile(g_szQueryFile, "db_selectPlayerRankUnknownCallback - szQuery: %s", szQuery);
			}
			g_dDb.Query(db_getPlayerRankUnknownCallback, szQuery, pack, DBPrio_Low);
		}
		else
			CPrintToChat(client, "%t", "SQLTwo7", g_szChatPrefix);
	}
}

public void db_getPlayerRankUnknownCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_getPlayerRankUnknownCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	char szSteamId[32];
	char szName[128];
	ReadPackString(pack, szSteamId, sizeof(szSteamId));
	ReadPackString(pack, szName, sizeof(szName));
	int points = ReadPackCell(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	delete pack;

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			int playerrank = results.FetchInt(0);

			CPrintToChatAll("%t", "SQL39", g_szChatPrefix, szName, playerrank, g_pr_RankedPlayers, points);
		}
		else {
			CPrintToChat(client, "%t", "SQL40", g_szChatPrefix, szName);
		}
	}
}

public void db_selectMapImprovement(int client, char szMapName[128])
{
	char szQuery[1024];

	Format(szQuery, sizeof(szQuery), "SELECT mapname, (SELECT count(1) FROM ck_playertimes b WHERE a.mapname = b.mapname AND b.style = 0) as total, (SELECT tier FROM ck_maptier b WHERE a.mapname = b.mapname) as tier FROM ck_playertimes a where mapname LIKE '%c%s%c' AND style = 0 LIMIT 1;", PERCENT, szMapName, PERCENT);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectMapImprovement - szQuery: %s", szQuery);
	}
	g_dDb.Query(db_selectMapImprovementCallback, szQuery, GetClientUserId(client), DBPrio_Low);
}

public void db_selectMapImprovementCallback(Database db, DBResultSet results, const char[] error, any userid)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_selectMapImprovementCallback): %s", error);
		return;
	}

	int client = GetClientOfUserId(userid);

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			char szMapName[32];
			int totalplayers;
			int tier;

			results.FetchString(0, szMapName, sizeof(szMapName));
			totalplayers = results.FetchInt(1);
			tier = results.FetchInt(2);

			g_szMiMapName[client] = szMapName;
			int type;
			type = g_MiType[client];

			// Map Completion Points
			int mapcompletion;
			if (tier == 1)
				mapcompletion = 25;
			else if (tier == 2)
				mapcompletion = 50;
			else if (tier == 3)
				mapcompletion = 100;
			else if (tier == 4)
				mapcompletion = 200;
			else if (tier == 5)
				mapcompletion = 400;
			else if (tier == 6)
				mapcompletion = 600;
			else if (tier == 7)
				mapcompletion = 800;
			else if (tier == 8)
				mapcompletion = 1000;
			else // no tier
				mapcompletion = 13;

			// Calculate Group Ranks
			float wrpoints;
			// float points;
			float g1points;
			float g2points;
			float g3points;
			float g4points;
			float g5points;

			// Group 1
			float fG1top;
			int g1top;
			int g1bot = 11;
			fG1top = (float(totalplayers) * g_Group1Pc);
			fG1top += 11.0; // Rank 11 is always End of Group 1
			g1top = RoundToCeil(fG1top);

			int g1difference = (g1top - g1bot);
			if (g1difference < 4)
				g1top = (g1bot + 4);


			// Group 2
			float fG2top;
			int g2top;
			int g2bot;
			g2bot = g1top + 1;
			fG2top = (float(totalplayers) * g_Group2Pc);
			fG2top += 11.0;
			g2top = RoundToCeil(fG2top);

			int g2difference = (g2top - g2bot);
			if (g2difference < 4)
				g2top = (g2bot + 4);

			// Group 3
			float fG3top;
			int g3top;
			int g3bot;
			g3bot = g2top + 1;
			fG3top = (float(totalplayers) * g_Group3Pc);
			fG3top += 11.0;
			g3top = RoundToCeil(fG3top);

			int g3difference = (g3top - g3bot);
			if (g3difference < 4)
				g3top = (g3bot + 4);

			// Group 4
			float fG4top;
			int g4top;
			int g4bot;
			g4bot = g3top + 1;
			fG4top = (float(totalplayers) * g_Group4Pc);
			fG4top += 11.0;
			g4top = RoundToCeil(fG4top);

			int g4difference = (g4top - g4bot);
			if (g4difference < 4)
				g4top = (g4bot + 4);

			// Group 5
			float fG5top;
			int g5top;
			int g5bot;
			g5bot = g4top + 1;
			fG5top = (float(totalplayers) * g_Group5Pc);
			fG5top += 11.0;
			g5top = RoundToCeil(fG5top);

			int g5difference = (g5top - g5bot);
			if (g5difference < 4)
				g5top = (g5bot + 4);

			// WR Points
			if (tier == 1)
			{
				wrpoints = ((float(totalplayers) * 1.75) / 6);
				wrpoints += 58.5;
				if (wrpoints < 250.0)
					wrpoints = 250.0;
			}
			else if (tier == 2)
			{
				wrpoints = ((float(totalplayers) * 2.8) / 5);
				wrpoints += 82.15;
				if (wrpoints < 500.0)
					wrpoints = 500.0;
			}
			else if (tier == 3)
			{
				wrpoints = ((float(totalplayers) * 3.5) / 4);
				if (wrpoints < 750.0)
					wrpoints = 750.0;
				else
					wrpoints += 117;
			}
			else if (tier == 4)
			{
				wrpoints = ((float(totalplayers) * 5.74) / 4);
				if (wrpoints < 1000.0)
					wrpoints = 1000.0;
				else
					wrpoints += 164.25;
			}
			else if (tier == 5)
			{
				wrpoints = ((float(totalplayers) * 7) / 4);
				if (wrpoints < 1250.0)
					wrpoints = 1250.0;
				else
					wrpoints += 234;
			}
			else if (tier == 6)
			{
				wrpoints = ((float(totalplayers) * 14) / 4);
				if (wrpoints < 1500.0)
					wrpoints = 1500.0;
				else
					wrpoints += 328;
			}
			else if (tier == 7)
			{
				wrpoints = ((float(totalplayers) * 21) / 4);
				if (wrpoints < 1750.0)
					wrpoints = 1750.0;
				else
					wrpoints += 420;
			}
			else if (tier == 8)
			{
				wrpoints = ((float(totalplayers) * 30) / 4);
				if (wrpoints < 2000.0)
					wrpoints = 2000.0;
				else
					wrpoints += 560;
			}
			else // no tier set
				wrpoints = 25.0;

			// Round WR points up
			int iwrpoints;
			iwrpoints = RoundToCeil(wrpoints);

			// Calculate Top 10 Points
			int rank2;
			float frank2;
			int rank3;
			float frank3;
			int rank4;
			float frank4;
			int rank5;
			float frank5;
			int rank6;
			float frank6;
			int rank7;
			float frank7;
			int rank8;
			float frank8;
			int rank9;
			float frank9;
			int rank10;
			float frank10;

			frank2 = (0.80 * iwrpoints);
			rank2 += RoundToCeil(frank2);
			frank3 = (0.75 * iwrpoints);
			rank3 += RoundToCeil(frank3);
			frank4 = (0.70 * iwrpoints);
			rank4 += RoundToCeil(frank4);
			frank5 = (0.65 * iwrpoints);
			rank5 += RoundToCeil(frank5);
			frank6 = (0.60 * iwrpoints);
			rank6 += RoundToCeil(frank6);
			frank7 = (0.55 * iwrpoints);
			rank7 += RoundToCeil(frank7);
			frank8 = (0.50 * iwrpoints);
			rank8 += RoundToCeil(frank8);
			frank9 = (0.45 * iwrpoints);
			rank9 += RoundToCeil(frank9);
			frank10 = (0.40 * iwrpoints);
			rank10 += RoundToCeil(frank10);

			// Calculate Group Points
			g1points = (wrpoints * 0.25);
			g2points = (g1points / 1.5);
			g3points = (g2points / 1.5);
			g4points = (g3points / 1.5);
			g5points = (g4points / 1.5);

			// Draw Menu Map Improvement Menu
			if (type == 0)
			{
				Menu mi = CreateMenu(MapImprovementMenuHandler);
				SetMenuTitle(mi, "[Point Reward: %s]\n------------------------------\nTier: %i\n \n[Completion Points]\n \nMap Finish Points: %i\n \n[Map Improvement Groups]\n \n[Group 1] Ranks 11-%i ~ %i Pts\n[Group 2] Ranks %i-%i ~ %i Pts\n[Group 3] Ranks %i-%i ~ %i Pts\n[Group 4] Ranks %i-%i ~ %i Pts\n[Group 5] Ranks %i-%i ~ %i Pts\n \nSR Pts: %i\n \nTotal Completions: %i\n \n",szMapName, tier, mapcompletion, g1top, RoundFloat(g1points), g2bot, g2top, RoundFloat(g2points), g3bot, g3top, RoundFloat(g3points), g4bot, g4top, RoundFloat(g4points), g5bot, g5top, RoundFloat(g5points), iwrpoints, totalplayers);
				// AddMenuItem(mi, "", "", ITEMDRAW_SPACER);
				AddMenuItem(mi, szMapName, "Top 10 Points");
				SetMenuOptionFlags(mi, MENUFLAG_BUTTON_EXIT);
				DisplayMenu(mi, client, MENU_TIME_FOREVER);
			}
			else // Draw Top 10 Points Menu
			{
				Menu mi = CreateMenu(MapImprovementTop10MenuHandler);
				SetMenuTitle(mi, "[Point Reward: %s]\n------------------------------\nTier: %i\n \n[Completion Points]\n \nMap Finish Points: %i\n \n[Top 10 Points]\n \nRank 1: %i Pts\nRank 2: %i Pts\nRank 3: %i Pts\nRank 4: %i Pts\nRank 5: %i Pts\nRank 6: %i Pts\nRank 7: %i Pts\nRank 8: %i Pts\nRank 9: %i Pts\nRank 10: %i Pts\n \nTotal Completions: %i\n",szMapName, tier, mapcompletion, iwrpoints, rank2, rank3, rank4, rank5, rank6, rank7, rank8, rank9, rank10, totalplayers);
				AddMenuItem(mi, "", "", ITEMDRAW_SPACER);
				SetMenuOptionFlags(mi, MENUFLAG_BUTTON_EXIT);
				DisplayMenu(mi, client, MENU_TIME_FOREVER);
			}
		}
		else
		{
			CPrintToChat(client, "%t", "SQL28", g_szChatPrefix);
		}
	}
}

public int MapImprovementMenuHandler(Menu mi, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char szMapName[128];
		GetMenuItem(mi, param2, szMapName, sizeof(szMapName));
		g_MiType[param1] = 1;
		db_selectMapImprovement(param1, szMapName);
	}
	if (action == MenuAction_End)
		delete mi;
}

public int MapImprovementTop10MenuHandler(Menu mi, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Cancel)
	{
		g_MiType[param1] = 0;
		db_selectMapImprovement(param1, g_szMiMapName[param1]);
	}
	if (action == MenuAction_End)
	{
		delete mi;
	}
}

public void db_selectCurrentMapImprovement()
{
	char szQuery[1024];
	Format(szQuery, sizeof(szQuery), "SELECT mapname, (SELECT count(1) FROM ck_playertimes b WHERE a.mapname = b.mapname AND b.style = 0) as total FROM ck_playertimes a where mapname = '%s' AND style = 0 LIMIT 0, 1;", g_szMapName);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectCurrentMapImprovement - szQuery: %s", szQuery);
	}
	g_dDb.Query(db_selectMapCurrentImprovementCallback, szQuery, _, DBPrio_Low);
}

public void db_selectMapCurrentImprovementCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_selectMapCurrentImprovementCallback): %s", error);
		if (!g_bServerDataLoaded)
			db_selectAnnouncements();
		return;
	}

	if (results.HasResults && results.FetchRow())
	{
		int totalplayers;
		totalplayers = results.FetchInt(1);

		// Group 1
		float fG1top;
		int g1top;
		int g1bot = 11;
		fG1top = (float(totalplayers) * g_Group1Pc);
		fG1top += 11.0; // Rank 11 is always End of Group 1
		g1top = RoundToCeil(fG1top);

		int g1difference = (g1top - g1bot);
		if (g1difference < 4)
			g1top = (g1bot + 4);

		g_G1Top = g1top;

		// Group 2
		float fG2top;
		int g2top;
		int g2bot;
		g2bot = g1top + 1;
		fG2top = (float(totalplayers) * g_Group2Pc);
		fG2top += 11.0;
		g2top = RoundToCeil(fG2top);
		g_G2Bot = g2bot;
		g_G2Top = g2top;

		int g2difference = (g2top - g2bot);
		if (g2difference < 4)
			g2top = (g2bot + 4);

		g_G2Bot = g2bot;
		g_G2Top = g2top;

		// Group 3
		float fG3top;
		int g3top;
		int g3bot;
		g3bot = g2top + 1;
		fG3top = (float(totalplayers) * g_Group3Pc);
		fG3top += 11.0;
		g3top = RoundToCeil(fG3top);

		int g3difference = (g3top - g3bot);
		if (g3difference < 4)
			g3top = (g3bot + 4);

		g_G3Bot = g3bot;
		g_G3Top = g3top;

		// Group 4
		float fG4top;
		int g4top;
		int g4bot;
		g4bot = g3top + 1;
		fG4top = (float(totalplayers) * g_Group4Pc);
		fG4top += 11.0;
		g4top = RoundToCeil(fG4top);

		int g4difference = (g4top - g4bot);
		if (g4difference < 4)
			g4top = (g4bot + 4);

		g_G4Bot = g4bot;
		g_G4Top = g4top;

		// Group 5
		float fG5top;
		int g5top;
		int g5bot;
		g5bot = g4top + 1;
		fG5top = (float(totalplayers) * g_Group5Pc);
		fG5top += 11.0;
		g5top = RoundToCeil(fG5top);

		int g5difference = (g5top - g5bot);
		if (g5difference < 4)
			g5top = (g5bot + 4);

		g_G5Bot = g5bot;
		g_G5Top = g5top;
	}
	else
	{
		PrintToServer("surftimer | No result found for map %s (db_selectMapCurrentImprovementCallback)", g_szMapName);
	}

	if (!g_bServerDataLoaded)
		db_selectAnnouncements();
}

public void db_selectMapNameEquals(int client, char[] szMapName, int style)
{
	char szQuery[256];
	Format(szQuery, sizeof(szQuery), "SELECT DISTINCT mapname FROM ck_zones WHERE mapname = '%s' LIMIT 1;", szMapName);

	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, style);
	WritePackString(pack, szMapName);

	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectMapNameEquals - szQuery: %s", szQuery);
	}
	g_dDb.Query(sql_selectMapNameEqualsCallback, szQuery, pack, DBPrio_Low);
}

public void sql_selectMapNameEqualsCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_selectMapNameEqualsCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int style = ReadPackCell(pack);
	char szMapName[128];
	ReadPackString(pack, szMapName, sizeof(szMapName));

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			results.FetchString(0, g_szMapNameFromDatabase[client], sizeof(g_szMapNameFromDatabase));
			if (style == 0)
			{
				g_ProfileStyleSelect[client] = 0;
				db_selectMapTopSurfers(client, g_szMapNameFromDatabase[client]);
			}
			else
			{
				g_ProfileStyleSelect[client] = style;
				db_selectStyleMapTopSurfers(client, g_szMapNameFromDatabase[client], style);
			}
		}
		else
		{
			Format(g_szMapNameFromDatabase[client], sizeof(g_szMapNameFromDatabase), "invalid");
			char szQuery[256];
			Format(szQuery, sizeof(szQuery), "SELECT DISTINCT mapname FROM ck_zones WHERE mapname LIKE '%c%s%c';", PERCENT, szMapName, PERCENT);
			if (g_cLogQueries.BoolValue)
			{
				LogToFile(g_szQueryFile, "sql_selectMapNameEqualsCallback - szQuery: %s", szQuery);
			}
			g_dDb.Query(sql_selectMapNameLikeCallback, szQuery, pack, DBPrio_Low);
			return;
		}
	}

	delete pack;
}

public void sql_selectMapNameLikeCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (sql_selectMapNameLikeCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = ReadPackCell(pack);
	int style = ReadPackCell(pack);
	char szMapName[128];
	ReadPackString(pack, szMapName, sizeof(szMapName));
	delete pack;

	if (results.HasResults)
	{
		int count = results.RowCount;
		if (count > 1)
		{
			char szMapName2[128];
			Menu menu = CreateMenu(ChooseMapMenuHandler);
			g_ProfileStyleSelect[client] = style;

			while (results.FetchRow())
			{
				results.FetchString(0, szMapName2, sizeof(szMapName2));
				AddMenuItem(menu, szMapName2, szMapName2);
			}

			SetMenuTitle(menu, "Choose a map:");
			SetMenuOptionFlags(menu, MENUFLAG_BUTTON_EXIT);
			DisplayMenu(menu, client, MENU_TIME_FOREVER);
		}
		else
		{
			if (results.FetchRow())
			{
				results.FetchString(0, g_szMapNameFromDatabase[client], sizeof(g_szMapNameFromDatabase));
				if (style == 0)
				{
					g_ProfileStyleSelect[client] = 0;
					db_selectMapTopSurfers(client, g_szMapNameFromDatabase[client]);
				}
				else
				{
					g_ProfileStyleSelect[client] = style;
					db_selectStyleMapTopSurfers(client, g_szMapNameFromDatabase[client], style);
				}
			}
			else
				CPrintToChat(client, "%t", "NoMapFound", g_szChatPrefix, szMapName);
		}
	}
	else
		CPrintToChat(client, "%t", "NoMapFound", g_szChatPrefix, szMapName);
}

public int ChooseMapMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		GetMenuItem(menu, param2, g_szMapNameFromDatabase[param1], sizeof(g_szMapNameFromDatabase));
		int style = g_ProfileStyleSelect[param1];
		if (style == 0)
		{
			g_ProfileStyleSelect[param1] = 0;
			db_selectMapTopSurfers(param1, g_szMapNameFromDatabase[param1]);
		}
		else
		{
			db_selectStyleMapTopSurfers(param1, g_szMapNameFromDatabase[param1], style);
		}
	}
	else if (action == MenuAction_End)
		delete menu;
}

public void db_selectMapCurrentWR(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[SurfTimer] SQL Error (db_selectMapCurrentWR): %s", error);
		delete pack;
		return;
	}

	if (results.HasResults && results.FetchRow())
	{
		ResetPack(pack);
		char szSteamId[32], szStyleType[5];
		ReadPackString(pack, szSteamId, sizeof(szSteamId));
		ReadPackString(pack, szStyleType, sizeof(szStyleType));
		int iLevel = ReadPackCell(pack);

		char sSteamId[32];
		results.FetchString(1, sSteamId, sizeof(sSteamId));
		int iStyle = results.FetchInt(2);

		if (StrEqual(szSteamId, sSteamId))
		{
			// Check if backup exists
			char sPathBack[256];
			if (StrEqual(szStyleType, "bonus"))
				if (iStyle == 0)
					BuildPath(Path_SM, sPathBack, sizeof(sPathBack), "%s%s_bonus_%i.rec.bak", CK_REPLAY_PATH, g_szMapName, iLevel);
				else
					BuildPath(Path_SM, sPathBack, sizeof(sPathBack), "%s%s_bonus_%i_style_%i.rec.bak", CK_REPLAY_PATH, g_szMapName, iLevel, iStyle);
			else if (StrEqual(szStyleType, "stage"))
				if (iStyle == 0)
					BuildPath(Path_SM, sPathBack, sizeof(sPathBack), "%s%s_stage_%i.rec.bak", CK_REPLAY_PATH, g_szMapName, iLevel);
				else
					BuildPath(Path_SM, sPathBack, sizeof(sPathBack), "%s%s_stage_%i_style_%i.rec.bak", CK_REPLAY_PATH, g_szMapName, iLevel, iStyle);
			else if (StrEqual(szStyleType, ""))
				if (iStyle == 0)
					BuildPath(Path_SM, sPathBack, sizeof(sPathBack), "%s%s.rec.bak", CK_REPLAY_PATH, g_szMapName);
				else
					BuildPath(Path_SM, sPathBack, sizeof(sPathBack), "%s%s_style_%i.rec.bak", CK_REPLAY_PATH, g_szMapName, iStyle);
			
			if (FileExists(sPathBack))
			{
				char sPath[256];
				if (StrEqual(szStyleType, "bonus"))
					if (iStyle == 0)
						BuildPath(Path_SM, sPath, sizeof(sPath), "%s%s_bonus_%i.rec", CK_REPLAY_PATH, g_szMapName, iLevel);
					else
						BuildPath(Path_SM, sPath, sizeof(sPath), "%s%s_bonus_%i_style_%i.rec", CK_REPLAY_PATH, g_szMapName, iLevel, iStyle);
				else if (StrEqual(szStyleType, "stage"))
					if (iStyle == 0)
						BuildPath(Path_SM, sPath, sizeof(sPath), "%s%s_stage_%i.rec", CK_REPLAY_PATH, g_szMapName, iLevel);
					else
						BuildPath(Path_SM, sPath, sizeof(sPath), "%s%s_stage_%i_style_%i.rec", CK_REPLAY_PATH, g_szMapName, iLevel, iStyle);
				else if (StrEqual(szStyleType, ""))
					if (iStyle == 0)
						BuildPath(Path_SM, sPath, sizeof(sPath), "%s%s.rec", CK_REPLAY_PATH, g_szMapName);
					else
						BuildPath(Path_SM, sPath, sizeof(sPath), "%s%s_style_%i.rec", CK_REPLAY_PATH, g_szMapName, iStyle);
				
				if (FileExists(sPath))
				{
					DeleteFile(sPath);
					RenameFile(sPathBack, sPath);
					setReplayTime(0, 0, 0);

					CreateTimer(5.0, FixBot_Off, _, TIMER_FLAG_NO_MAPCHANGE);
					CreateTimer(10.0, FixBot_On, _, TIMER_FLAG_NO_MAPCHANGE);
				}
			}
		}
	}
	
	delete pack;
}

// sm_pr command
public void db_viewPlayerPr(int client, char szSteamId[32], char szMapName[128])
{
	char szQuery[1024];
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackString(pack, szSteamId);

	char szUpper[128];
	char szUpper2[128];
	Format(szUpper, 128, "%s", szMapName);
	Format(szUpper2, 128, "%s", g_szMapName);
	StringToUpper(szUpper);
	StringToUpper(szUpper2);

	if (StrEqual(szUpper, szUpper2)) // is the mapname the current map?
	{
		WritePackString(pack, szMapName);
		WritePackCell(pack, g_TotalStages);
		WritePackCell(pack, g_mapZoneGroupCount);
		// first select map time
		Format(szQuery, sizeof(szQuery), "SELECT steamid, name, mapname, runtimepro, (select count(name) FROM ck_playertimes WHERE mapname = '%s' AND style = 0) as total FROM ck_playertimes WHERE runtimepro <= (SELECT runtimepro FROM ck_playertimes WHERE steamid = '%s' AND mapname = '%s' AND runtimepro > -1.0 AND style = 0) AND mapname = '%s' AND runtimepro > -1.0 AND style = 0 ORDER BY runtimepro;", szMapName, szSteamId, szMapName, szMapName);
		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "db_viewPlayerPr - szQuery: %s", szQuery);
		}
		g_dDb.Query(SQL_ViewPlayerPrMaptimeCallback, szQuery, pack, DBPrio_Low);
	}
	else
	{
		Format(szQuery, sizeof(szQuery), "SELECT mapname FROM ck_maptier WHERE mapname LIKE '%c%s%c' LIMIT 1;", PERCENT, szMapName, PERCENT);
		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "db_viewPlayerPr - szQuery: %s", szQuery);
		}
		g_dDb.Query(SQL_ViewMapNamePrCallback, szQuery, pack, DBPrio_Low);
	}
}

public void SQL_ViewMapNamePrCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[surftimer] SQL Error (SQL_ViewMapNamePrCallback): %s ", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	char szSteamId[32];
	ReadPackString(pack, szSteamId, 32);

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			char szMapName[128];
			results.FetchString(0, szMapName, 128);
			WritePackString(pack, szMapName);

			char szQuery[1024];
			Format(szQuery, sizeof(szQuery), "SELECT mapname, (SELECT COUNT(1) FROM ck_zones WHERE zonetype = '3' AND mapname = '%s') AS stages, (SELECT COUNT(DISTINCT zonegroup) FROM ck_zones WHERE mapname = '%s' AND zonegroup > 0) AS bonuses FROM ck_maptier WHERE mapname = '%s';", szMapName, szMapName, szMapName);
			if (g_cLogQueries.BoolValue)
			{
				LogToFile(g_szQueryFile, "SQL_ViewMapNamePrCallback - szQuery: %s", szQuery);
			}
			g_dDb.Query(SQL_ViewPlayerPrMapInfoCallback, szQuery, pack, DBPrio_Low);
			return;
		}

		CPrintToChat(client, "%t", "SQLTwo1", g_szChatPrefix);
	}

	delete pack;
}

public void SQL_ViewPlayerPrMapInfoCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[surftimer] SQL Error (SQL_ViewPlayerPrMapInfoCallback): %s ", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	char szSteamId[32];
	char szMapName[128];
	ReadPackString(pack, szSteamId, 32);
	ReadPackString(pack, szMapName, 128);

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			g_totalStagesPr[client] = results.FetchInt(1);
			g_totalBonusesPr[client] = results.FetchInt(2);

			if (g_totalStagesPr[client] != 0)
				g_totalStagesPr[client]++;

			if (g_totalBonusesPr[client] != 0)
				g_totalBonusesPr[client]++;

			char szQuery[1024];
			Format(szQuery, sizeof(szQuery), "SELECT steamid, name, mapname, runtimepro, (select count(name) FROM ck_playertimes WHERE mapname = '%s' AND style = 0) as total FROM ck_playertimes WHERE runtimepro <= (SELECT runtimepro FROM ck_playertimes WHERE steamid = '%s' AND mapname = '%s' AND runtimepro > -1.0 AND style = 0) AND mapname = '%s' AND runtimepro > -1.0 AND style = 0 ORDER BY runtimepro;", szMapName, szSteamId, szMapName, szMapName);
			if (g_cLogQueries.BoolValue)
			{
				LogToFile(g_szQueryFile, "SQL_ViewPlayerPrMapInfoCallback - szQuery: %s", szQuery);
			}
			g_dDb.Query(SQL_ViewPlayerPrMaptimeCallback, szQuery, pack, DBPrio_Low);
			return;
		}
	}
	
	delete pack;
}

public void SQL_ViewPlayerPrMaptimeCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[surftimer] SQL Error (SQL_ViewPlayerPrMaptimeCallback): %s ", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	char szSteamId[32];
	char szMapName[128];
	ReadPackString(pack, szSteamId, 32);
	ReadPackString(pack, szMapName, 128);

	if (IsValidClient(client))
	{
		float time = -1.0;
		int total;
		int rank = 0;
		if (results.HasResults && IsValidClient(client))
		{
			int i = 1;
			char szSteamId2[32];
			while (results.FetchRow())
			{
				if (i == 1)
					total = results.FetchInt(4);
				i++;
				rank++;

				results.FetchString(0, szSteamId2, 32);
				if (StrEqual(szSteamId, szSteamId2))
				{
					time = results.FetchFloat(3);
					break;
				}
				else
					continue;
			}
		}
		else
		{
			time = -1.0;
		}

		// CPrintToChat(client, "total: %i , runtimepro: %f", total, time);

		WritePackFloat(pack, time);
		WritePackCell(pack, total);
		WritePackCell(pack, rank);

		char szQuery[1024];

		Format(szQuery, sizeof(szQuery), "SELECT db1.steamid, db1.name, db1.mapname, db1.runtimepro, db1.stage, (SELECT count(name) FROM ck_wrcps WHERE style = 0 AND mapname = db1.mapname AND stage = db1.stage AND runtimepro > -1.0 AND runtimepro <= db1.runtimepro) AS `rank`, (SELECT count(name) FROM ck_wrcps WHERE style = 0 AND mapname = db1.mapname AND stage = db1.stage AND runtimepro > -1.0) AS total FROM ck_wrcps db1 WHERE db1.mapname = '%s' AND db1.steamid = '%s' AND db1.runtimepro > -1.0 AND db1.style = 0 ORDER BY stage ASC", szMapName, szSteamId);
		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "SQL_ViewPlayerPrMaptimeCallback - szQuery: %s", szQuery);
		}
		g_dDb.Query(SQL_ViewPlayerPrMaptimeCallback2, szQuery, pack, DBPrio_Low);
	}

	delete pack;
}

public void SQL_ViewPlayerPrMaptimeCallback2(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[surftimer] SQL Error (SQL_ViewPlayerPrMaptimeCallback2): %s ", error);
		delete pack;
		return;
	}

	char szSteamId[32];
	char szMapName[128];

	ResetPack(pack);
	int client = ReadPackCell(pack);
	ReadPackString(pack, szSteamId, 32);
	ReadPackString(pack, szMapName, 128);
	float time = ReadPackFloat(pack);
	int total = ReadPackCell(pack);
	int rank = ReadPackCell(pack);
	delete pack;

	int target = g_iPrTarget[client];
	int stage;
	int stagerank[CPLIMIT];
	int totalcompletes[CPLIMIT];
	int totalstages = 0;
	float stagetime[CPLIMIT];

	for (int i = 1; i < CPLIMIT; i++)
	{
		stagetime[i] = -1.0;
		stagerank[i] = 0;
		totalcompletes[i] = 0;
	}

	if (results.HasResults)
	{
		while (results.FetchRow())
		{
			totalstages++;
			stage = results.FetchInt(4);
			stagetime[stage] = results.FetchFloat(3);
			stagerank[stage] = results.FetchInt(5);
			totalcompletes[stage] = results.FetchInt(6);
		}
	}

	char szMapInfo[256];
	char szRuntimepro[64];
	char szStageInfo[CPLIMIT][256];
	char szRuntimestages[CPLIMIT][64];
	char szBonusInfo[MAXZONEGROUPS][256];

	Menu menu;
	menu = CreateMenu(PrMenuHandler);
	char szName[MAX_NAME_LENGTH];
	GetClientName(target, szName, sizeof(szName));

	SetMenuTitle(menu, "Personal Record for %s\n%s\n \n", szName, szMapName);
	if (time != -1.0)
	{
		FormatTimeFloat(0, time, 3, szRuntimepro, 64);
		Format(szMapInfo, 256, "Map Time: %s\nRank: %i/%i\n \n", szRuntimepro, rank, total);
	}
	else
	{
		Format(szMapInfo, 256, "Map Time: None\n \n", szRuntimepro, rank, total);
	}
	AddMenuItem(menu, "map", szMapInfo);

	if (StrEqual(szMapName, g_szMapName))
	{
		g_totalBonusesPr[client] = g_mapZoneGroupCount;

		if (g_bhasStages)
			g_totalStagesPr[client] = g_TotalStages;
		else
			g_totalStagesPr[client] = 0;
	}

	if (g_totalStagesPr[client] > 0)
	{
		for (int i = 1;i <= g_totalStagesPr[client]; i++)
		{
			if (stagetime[i] != -1.0)
			{
				FormatTimeFloat(0, stagetime[i], 3, szRuntimestages[i], 64);
				Format(szStageInfo[i], 256, "Stage %i: %s\nRank: %i/%i\n \n", i, szRuntimestages[i], stagerank[i], totalcompletes[i]);
			}
			else
			{
				Format(szStageInfo[i], 256, "Stage %i: None\n \n", i);
			}

			AddMenuItem(menu, "stage", szStageInfo[i]);
		}
	}

	if (g_totalBonusesPr[client] > 1)
	{
		for (int i = 1; i < g_totalBonusesPr[client]; i++)
		{
			if (g_fPersonalRecordBonus[i][client] != 0.0)
				Format(szBonusInfo[i], 256, "Bonus %i: %s\nRank: %i/%i\n \n", i, g_szPersonalRecordBonus[i][target], g_MapRankBonus[i][target], g_iBonusCount[i]);
			else
				Format(szBonusInfo[i], 256, "Bonus %i: None\n \n", i);

			AddMenuItem(menu, "bonus", szBonusInfo[i]);
		}
	}

	SetMenuOptionFlags(menu, MENUFLAG_BUTTON_EXIT);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
	return;
}

public int PrMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		delete menu;
	}
}

// VIP

// fluffys start vip & admins

public void db_CheckVIPAdmin(int client, char[] szSteamID)
{
	char szQuery[1024];
	Format(szQuery, sizeof(szQuery), "SELECT vip, admin, zoner FROM ck_vipadmins WHERE steamid = '%s';", szSteamID);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_CheckVIPAdmin - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_CheckVIPAdminCallback, szQuery, GetClientUserId(client), DBPrio_Low);
}

public void SQL_CheckVIPAdminCallback(Database db, DBResultSet results, const char[] error, any userid)
{
	int client = GetClientOfUserId(userid);

	if (IsValidClient(client))
	{
		char szSteamId[32];
		getSteamIDFromClient(client, szSteamId, 32);

		if (!IsValidDatabase(db, error))
		{
			LogError("[surftimer] SQL Error (SQL_CheckVIPAdminCallback): %s", error);

			if (!g_bSettingsLoaded[client])
				LoadClientSetting(client, g_iSettingToLoad[client]);
		}

		g_bVip[client] = false;
		g_bZoner[client] = false;

		if (results.HasResults && results.FetchRow())
		{
			g_bVip[client] = view_as<bool>(results.FetchInt(0));
			g_bZoner[client] = view_as<bool>(results.FetchInt(2));
		}

		if (!g_bVip[client] || !g_bZoner[client]) // No VIP or Zoner from database, let's check flags
		{
			if (CheckCommandAccess(client, "", g_VipFlag))
				g_bVip[client] = true;

			if (CheckCommandAccess(client, "", g_ZonerFlag))
				g_bZoner[client] = true;
		}

		if (g_bCheckCustomTitle[client])
		{
			db_viewCustomTitles(client, g_szSteamID[client]);
			g_bCheckCustomTitle[client] = false;
		}

		if (!g_bSettingsLoaded[client])
		{
			g_fTick[client][1] = GetGameTime();
			float tick = g_fTick[client][1] - g_fTick[client][0];
			LogToFileEx(g_szLogFile, "[SurfTimer] %s: Finished db_CheckVIPAdmin in %fs", g_szSteamID[client], tick);
			g_fTick[client][0] = GetGameTime();


			LoadClientSetting(client, g_iSettingToLoad[client]);
		}

		//db_CheckVIPAdmin(client, g_szSteamID[client]); this causes infinite loop
		// more details in https://github.com/surftimer/Surftimer-olokos/issues/184
	}
}

public void db_checkCustomPlayerTitle(int client, char[] szSteamID, char[] arg)
{
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackString(pack, szSteamID);
	WritePackString(pack, arg);

	char szQuery[512];
	Format(szQuery, sizeof(szQuery), "SELECT `steamid` FROM `ck_vipadmins` WHERE `steamid` = '%s';", szSteamID);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_checkCustomPlayerTitle - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_checkCustomPlayerTitleCallback, szQuery, pack, DBPrio_Low);

}

public void SQL_checkCustomPlayerTitleCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[surftimer] SQL Error (SQL_checkCustomPlayerTitleCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	char szSteamID[32];
	char arg[128];
	ReadPackString(pack, szSteamID, 32);
	ReadPackString(pack, arg, 128);
	delete pack;

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			db_updateCustomPlayerTitle(client, szSteamID, arg);
		}
		else
		{
			db_insertCustomPlayerTitle(client, szSteamID, arg);
		}
	}
}

public void db_checkCustomPlayerNameColour(int client, char[] szSteamID, char[] arg)
{
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackString(pack, szSteamID);
	WritePackString(pack, arg);

	char szQuery[512];
	Format(szQuery, sizeof(szQuery), "SELECT `steamid` FROM `ck_vipadmins` WHERE `steamid` = '%s';", szSteamID);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_checkCustomPlayerNameColour - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_checkCustomPlayerNameColourCallback, szQuery, pack, DBPrio_Low);

}

public void SQL_checkCustomPlayerNameColourCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[surftimer] SQL Error (SQL_checkCustomPlayerNameColourCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	char szSteamID[32];
	char arg[128];
	ReadPackString(pack, szSteamID, 32);
	ReadPackString(pack, arg, 128);
	delete pack;

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			db_updateCustomPlayerNameColour(client, szSteamID, arg);
		}
		else
		{
			CPrintToChat(client, "%t", "SQLTwo2", g_szChatPrefix);
		}
	}
}

public void db_checkCustomPlayerTextColour(int client, char[] szSteamID, char[] arg)
{
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackString(pack, szSteamID);
	WritePackString(pack, arg);

	char szQuery[512];
	Format(szQuery, sizeof(szQuery), "SELECT `steamid` FROM `ck_vipadmins` WHERE `steamid` = '%s';", szSteamID);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_checkCustomPlayerTextColour - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_checkCustomPlayerTextColourCallback, szQuery, pack, DBPrio_Low);

}

public void SQL_checkCustomPlayerTextColourCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[surftimer] SQL Error (SQL_checkCustomPlayerTextColourCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	char szSteamID[32];
	char arg[128];
	ReadPackString(pack, szSteamID, 32);
	ReadPackString(pack, arg, 128);
	delete pack;

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			db_updateCustomPlayerTextColour(client, szSteamID, arg);
		}
		else
		{
			CPrintToChat(client, "%t", "SQLTwo3", g_szChatPrefix);
		}
	}
}


public void db_insertCustomPlayerTitle(int client, char[] szSteamID, char[] arg)
{
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackString(pack, szSteamID);

	char szQuery[512];
	Format(szQuery, sizeof(szQuery), "INSERT INTO `ck_vipadmins` (steamid, title, inuse) VALUES ('%s', '%s', 1);", szSteamID, arg);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_insertCustomPlayerTitle - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_insertCustomPlayerTitleCallback, szQuery, pack, DBPrio_Low);
}

public void SQL_insertCustomPlayerTitleCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	char szSteamID[32];
	ReadPackString(pack, szSteamID, 32);
	delete pack;

	PrintToServer("Successfully inserted custom title.");

	if (IsValidClient(client))
	{
		db_viewCustomTitles(client, szSteamID);
	}
}

public void db_updateCustomPlayerTitle(int client, char[] szSteamID, char[] arg)
{
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackString(pack, szSteamID);

	char szQuery[512];
	Format(szQuery, sizeof(szQuery), "UPDATE `ck_vipadmins` SET `title` = '%s' WHERE `steamid` = '%s';", arg, szSteamID);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_updateCustomPlayerTitle - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_updateCustomPlayerTitleCallback, szQuery, pack, DBPrio_Low);
}

public void SQL_updateCustomPlayerTitleCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	char szSteamID[32];
	ReadPackString(pack, szSteamID, 32);
	delete pack;

	PrintToServer("Successfully updated custom title.");
	if (IsValidClient(client))
	{
		db_viewCustomTitles(client, szSteamID);
	}
}

public void db_updateCustomPlayerNameColour(int client, char[] szSteamID, char[] arg)
{
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackString(pack, szSteamID);

	char szQuery[512];
	Format(szQuery, sizeof(szQuery), "UPDATE `ck_vipadmins` SET `namecolour` = '%s' WHERE `steamid` = '%s';", arg, szSteamID);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_updateCustomPlayerNameColour - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_updateCustomPlayerNameColourCallback, szQuery, pack, DBPrio_Low);
}

public void SQL_updateCustomPlayerNameColourCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	char szSteamID[32];
	ReadPackString(pack, szSteamID, 32);
	delete pack;

	PrintToServer("Successfully updated custom player colour");
	if (IsValidClient(client))
	{
		db_viewCustomTitles(client, szSteamID);
	}
}

public void db_updateCustomPlayerTextColour(int client, char[] szSteamID, char[] arg)
{
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackString(pack, szSteamID);

	char szQuery[512];
	Format(szQuery, sizeof(szQuery), "UPDATE `ck_vipadmins` SET `textcolour` = '%s' WHERE `steamid` = '%s';", arg, szSteamID);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_updateCustomPlayerTextColour - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_updateCustomPlayerTextColourCallback, szQuery, pack, DBPrio_Low);
}

public void SQL_updateCustomPlayerTextColourCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	char szSteamID[32];
	ReadPackString(pack, szSteamID, 32);
	delete pack;

	PrintToServer("Successfully updated custom player text colour");
	if (IsValidClient(client))
	{
		db_viewCustomTitles(client, szSteamID);
	}
}

public void db_toggleCustomPlayerTitle(int client, char[] szSteamID)
{
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackString(pack, szSteamID);

	char szQuery[512];
	if (g_bDbCustomTitleInUse[client])
	{
		Format(szQuery, sizeof(szQuery), "UPDATE `ck_vipadmins` SET `inuse` = '0' WHERE `steamid` = '%s';", szSteamID);
	}
	else
	{
		Format(szQuery, sizeof(szQuery), "UPDATE `ck_vipadmins` SET `inuse` = '1' WHERE `steamid` = '%s';", szSteamID);
	}

	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_toggleCustomPlayerTitle - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_insertCustomPlayerTitleCallback, szQuery, pack, DBPrio_Low);
}

public void db_viewCustomTitles(int client, char[] szSteamID)
{
	char szQuery[728];

	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackString(pack, szSteamID);
	Format(szQuery, sizeof(szQuery), "SELECT `title`, `namecolour`, `textcolour`, `inuse`, `vip`, `zoner`, `joinmsg` FROM `ck_vipadmins` WHERE `steamid` = '%s';", szSteamID);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewCustomTitles - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_viewCustomTitlesCallback, szQuery, pack, DBPrio_Low);
}

public void SQL_viewCustomTitlesCallback(Database db, DBResultSet results, const char[] error, DataPack pack) 
{
	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	char szSteamID[32];
	ReadPackString(pack, szSteamID, 32);
	delete pack;

	if (!IsValidDatabase(db, error))
	{
		LogError("[surftimer] SQL Error (SQL_viewCustomTitlesCallback): %s ", error);
		if (IsValidClient(client) && !g_bSettingsLoaded[client])
			LoadClientSetting(client, g_iSettingToLoad[client]);
		return;
	}

	if (IsValidClient(client))
	{
		g_bDbCustomTitleInUse[client] = false;
		g_bHasCustomTextColour[client] = false;
		g_bdbHasCustomTitle[client] = false;

		if (results.HasResults && results.FetchRow())
		{
			g_bdbHasCustomTitle[client] = true;
			results.FetchString(0, g_szCustomTitleColoured[client], sizeof(g_szCustomTitleColoured));
			
			Format(g_pr_chat_coloredrank[client], 1024, "%s", g_szCustomTitleColoured[client]);

			char szTitle[1024];
			Format(szTitle, 1024, "%s", g_szCustomTitleColoured[client]);
			parseColorsFromString(szTitle, 1024);
			Format(g_pr_rankname[client], 1024, "%s", szTitle);
			Format(g_pr_rankname_style[client], 1024, "%s", szTitle);
			Format(g_szCustomTitle[client], 1024, "%s", szTitle);

			if (!results.IsFieldNull(6) && IsPlayerVip(client, true, false))
				results.FetchString(6, g_szCustomJoinMsg[client], sizeof(g_szCustomJoinMsg));
			else
				Format(g_szCustomJoinMsg[client], sizeof(g_szCustomJoinMsg), "none");

			if (results.FetchInt(3) == 0)
			{
				g_bDbCustomTitleInUse[client] = false;
			}
			else
			{
				g_bDbCustomTitleInUse[client] = true;
				g_iCustomColours[client][0] = results.FetchInt(1);

				g_iCustomColours[client][1] = results.FetchInt(2);
				g_bHasCustomTextColour[client] = true;
			}
		}
		else
		{
			g_bDbCustomTitleInUse[client] = false;
			g_bHasCustomTextColour[client] = false;
			g_bdbHasCustomTitle[client] = false;
		}

		if (g_bUpdatingColours[client])
			CustomTitleMenu(client);

		g_bUpdatingColours[client] = false;

		if (!g_bSettingsLoaded[client])
		{
			g_fTick[client][1] = GetGameTime();
			float tick = g_fTick[client][1] - g_fTick[client][0];
			LogToFileEx(g_szLogFile, "[SurfTimer] %s: Finished db_viewCustomTitles in %fs", g_szSteamID[client], tick);

			g_fTick[client][0] = GetGameTime();
			LoadClientSetting(client, g_iSettingToLoad[client]);
		}
	}
}

public void db_viewPlayerColours(int client, char szSteamId[32], int type)
{
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, type); // 10 = name colour, 1 = text colour

	char szQuery[512];
	Format(szQuery, sizeof(szQuery), "SELECT steamid, namecolour, textcolour FROM ck_vipadmins WHERE `steamid` = '%s';", szSteamId);

	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_viewPlayerColours - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_ViewPlayerColoursCallback, szQuery, pack, DBPrio_Low);
}

public void SQL_ViewPlayerColoursCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[surftimer] SQL Error (SQL_ViewPlayerColoursCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));
	int type = ReadPackCell(pack); // 0 = name colour, 1 = text colour
	delete pack;

	if (results.HasResults && results.FetchRow())
	{
		char szSteamId[32];
		int colour[2];

		// get the result
		results.FetchString(0, szSteamId, 32);
		colour[0] = results.FetchInt(1);
		colour[1] = results.FetchInt(2);

		char szColour[32];
		getColourName(client, szColour, 32, colour[type]);

		// change title menu
		char szTitle[1024];
		char szType[32];
		switch (type)
		{
			case 0:
			{
				Format(szTitle, 1024, "Changing Name Colour (Current: %s):\n \n", szColour);
				Format(szType, 32, "name");
			}
			case 1:
			{
				Format(szTitle, 1024, "Changing Text Colour (Current: %s):\n \n", szColour);
				Format(szType, 32, "text");
			}
		}

		Menu changeColoursMenu = new Menu(changeColoursMenuHandler);

		changeColoursMenu.SetTitle(szTitle);

		changeColoursMenu.AddItem(szType, "White");
		changeColoursMenu.AddItem(szType, "Dark Red");
		changeColoursMenu.AddItem(szType, "Green");
		changeColoursMenu.AddItem(szType, "Lime Green");
		changeColoursMenu.AddItem(szType, "Blue");
		changeColoursMenu.AddItem(szType, "Moss Green");
		changeColoursMenu.AddItem(szType, "Red");
		changeColoursMenu.AddItem(szType, "Grey");
		changeColoursMenu.AddItem(szType, "Yellow");
		changeColoursMenu.AddItem(szType, "Light Blue");
		changeColoursMenu.AddItem(szType, "Dark Blue");
		changeColoursMenu.AddItem(szType, "Pink");
		changeColoursMenu.AddItem(szType, "Light Red");
		changeColoursMenu.AddItem(szType, "Purple");
		changeColoursMenu.AddItem(szType, "Dark Grey");
		changeColoursMenu.AddItem(szType, "Orange");

		changeColoursMenu.ExitButton = true;
		changeColoursMenu.Display(client, MENU_TIME_FOREVER);
	}
}

public int changeColoursMenuHandler(Handle menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		char szType[32];
		int type;
		GetMenuItem(menu, item, szType, sizeof(szType));
		if (StrEqual(szType, "name"))
			type = 0;
		else if (StrEqual(szType, "text"))
			type = 1;

		switch (item)
		{
			case 0:db_updateColours(client, g_szSteamID[client], 0, type);
			case 1:db_updateColours(client, g_szSteamID[client], 1, type);
			case 2:db_updateColours(client, g_szSteamID[client], 2, type);
			case 3:db_updateColours(client, g_szSteamID[client], 3, type);
			case 4:db_updateColours(client, g_szSteamID[client], 4, type);
			case 5:db_updateColours(client, g_szSteamID[client], 5, type);
			case 6:db_updateColours(client, g_szSteamID[client], 6, type);
			case 7:db_updateColours(client, g_szSteamID[client], 7, type);
			case 8:db_updateColours(client, g_szSteamID[client], 8, type);
			case 9:db_updateColours(client, g_szSteamID[client], 9, type);
			case 10:db_updateColours(client, g_szSteamID[client], 10, type);
			case 11:db_updateColours(client, g_szSteamID[client], 11, type);
			case 12:db_updateColours(client, g_szSteamID[client], 12, type);
			case 13:db_updateColours(client, g_szSteamID[client], 13, type);
			case 14:db_updateColours(client, g_szSteamID[client], 14, type);
			case 15:db_updateColours(client, g_szSteamID[client], 15, type);
		}
	}
	else
	if (action == MenuAction_Cancel)
	{
		CustomTitleMenu(client);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public void db_updateColours(int client, char szSteamId[32], int newColour, int type)
{
	char szQuery[512];
	switch (type)
	{
		case 0: Format(szQuery, sizeof(szQuery), "UPDATE ck_vipadmins SET namecolour = %i WHERE steamid = '%s';", newColour, szSteamId);
		case 1: Format(szQuery, sizeof(szQuery), "UPDATE ck_vipadmins SET textcolour = %i WHERE steamid = '%s';", newColour, szSteamId);
	}

	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_updateColours - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_UpdatePlayerColoursCallback, szQuery, GetClientUserId(client), DBPrio_Low);
}

public void SQL_UpdatePlayerColoursCallback(Database db, DBResultSet results, const char[] error, any userid)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[surftimer] SQL Error (SQL_UpdatePlayerColoursCallback): %s", error);
		return;
	}

	int client = GetClientOfUserId(userid);

	if (IsValidClient(client))
	{
		g_bUpdatingColours[client] = true;
		db_viewCustomTitles(client, g_szSteamID[client]);
	}
}

// fluffys end custom titles

// WR Announcements
public void db_selectAnnouncements()
{
	char szQuery[1024];
	char szEscServerName[128];
	g_dDb.Escape(g_sServerName, szEscServerName, sizeof(szEscServerName));
	Format(szQuery, sizeof(szQuery), "SELECT `id` FROM `ck_announcements` WHERE `server` != '%s' AND `id` > %d", szEscServerName, g_iLastID);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectAnnouncements - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_SelectAnnouncementsCallback, szQuery, _, DBPrio_Low);
}

public void SQL_SelectAnnouncementsCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[surftimer] SQL Error (SQL_SelectAnnouncementsCallback): %s", error);

		if (!g_bServerDataLoaded)
			loadAllClientSettings();
		return;
	}

	if (results.HasResults)
	{
		while (results.FetchRow())
		{
			int id = results.FetchInt(0);
			if (id > g_iLastID)
				g_iLastID = id;
		}
	}

	if (!g_bServerDataLoaded)
	{
		g_fServerLoading[1] = GetGameTime();
		g_bHasLatestID = true;
		float time = g_fServerLoading[1] - g_fServerLoading[0];
		LogToFileEx(g_szLogFile, "[SurfTimer] Finished loading server settings in %fs", time);
		loadAllClientSettings();
	} 
}

public void db_insertAnnouncement(int client, char szName[128], char szMapName[128], int szMode, char szTime[32], int szGroup)
{
	if (g_iServerID == -1)
		return;

	char szQuery[512];
	char szEscServerName[128];
	g_dDb.Escape(g_sServerName, szEscServerName, sizeof(szEscServerName));
	Format(szQuery, sizeof(szQuery), "INSERT INTO `ck_announcements` (`server`, `steamid`, `name`, `mapname`, `mode`, `time`, `group`) VALUES ('%s', '%s', '%s', '%s', '%i', '%s', '%i');", szEscServerName, g_szSteamID[client], szName, szMapName, szMode, szTime, szGroup);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_insertAnnouncement - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_InsertAnnouncementCallback, szQuery, _, DBPrio_Low);
}

public void db_checkAnnouncements()
{
	char szQuery[512];
	char szEscServerName[128];
	g_dDb.Escape(g_sServerName, szEscServerName, sizeof(szEscServerName));
	Format(szQuery, sizeof(szQuery), "SELECT `id`, `server`, `name`, `mapname`, `mode`, `time`, `group` FROM `ck_announcements` WHERE `server` != '%s' AND `id` > %d;", szEscServerName, g_iLastID);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_checkAnnouncements - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_CheckAnnouncementsCallback, szQuery, _, DBPrio_Low);
}

public void SQL_CheckAnnouncementsCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[surftimer] SQL Error (SQL_CheckAnnouncementsCallback): %s", error);
		return;
	}

	if (results.HasResults)
	{
		while (results.FetchRow())
		{
			int id = results.FetchInt(0);
			int mode = results.FetchInt(4);
			int group = results.FetchInt(6);
			char szServerName[256], szName[128], szMapName[128], szTime[32];
			results.FetchString(1, szServerName, sizeof(szServerName));
			results.FetchString(2, szName, sizeof(szName));
			results.FetchString(3, szMapName, sizeof(szMapName));
			results.FetchString(5, szTime, sizeof(szTime));

			if (id > g_iLastID)
			{
				// Send Server Announcement
				g_iLastID = id;
				CPrintToChatAll("%t", "SQLTwo4.1");
				if (mode == 0)
					CPrintToChatAll("%t", "SQLTwo4.2", g_szChatPrefix, szName, szMapName, szServerName, szTime);
				else if (mode == 1)
					CPrintToChatAll("%t", "SQLTwo4.2Bonus", g_szChatPrefix, szName, szMapName, group, szServerName, szTime);
				CPrintToChatAll("%t", "SQLTwo4.3");
			}
		}
	}
}

public void db_selectMapCycle()
{
	char szQuery[128];
	Format(szQuery, sizeof(szQuery), "SELECT mapname, tier FROM ck_maptier ORDER BY mapname ASC");
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectMapCycle - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_SelectMapCycleCallback, szQuery, _, DBPrio_Low);
}

public void SQL_SelectMapCycleCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[surftimer] SQL Error (SQL_SelectMapCycleCallback): %s", error);
		return;
	}

	g_pr_MapCount[0] = 0;
	ClearArray(g_MapList);

	if (results.HasResults)
	{
		char szMapname[128];
		int tier;

		while (results.FetchRow())
		{
			g_pr_MapCount[0]++;
			results.FetchString(0, szMapname, sizeof(szMapname));
			tier = results.FetchInt(1);
			// No out of bounds arrays please
			if (tier > 8)
				tier = 8;
			else if (tier < 1)
				tier = 1;

			g_pr_MapCount[tier]++;
			PushArrayString(g_MapList, szMapname);
		}
	}
}

public void db_setJoinMsg(int client, char[] szArg)
{
	char szQuery[512];
	Format(szQuery, sizeof(szQuery), "UPDATE ck_vipadmins SET joinmsg = '%s' WHERE steamid = '%s';", szArg, g_szSteamID[client]);
	Format(g_szCustomJoinMsg[client], sizeof(g_szCustomJoinMsg), "%s", szArg);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_setJoinMsg - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_SetJoinMsgCallback, szQuery, GetClientUserId(client), DBPrio_Low);
}

public void SQL_SetJoinMsgCallback(Database db, DBResultSet results, const char[] error, any userid)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[surftimer] SQL Error (SQL_SetJoinMsgCallback): %s", error);
		return;
	}

	int client = GetClientOfUserId(userid);

	if (IsValidClient(client))
	{
		if (StrEqual(g_szCustomJoinMsg[client], "none"))
			CPrintToChat(client, "%t", "SQLTwo5", g_szChatPrefix);
		else
			CPrintToChat(client, "%t", "SQLTwo6", g_szChatPrefix, g_szCustomJoinMsg[client]);
	}
}

public void db_selectCPR(int client, int rank, const char szMapName[128], const char szSteamId[32])
{
	Handle pack = CreateDataPack();
	WritePackCell(pack, GetClientUserId(client));
	WritePackCell(pack, rank);
	WritePackString(pack, szSteamId);

	char szQuery[512];
	Format(szQuery, sizeof(szQuery), "SELECT `steamid`, `name`, `mapname`, `runtimepro`, velStartXY, velStartXYZ, velStartZ, velEndXY, velEndXYZ, velEndZ FROM `ck_playertimes` WHERE `steamid` = '%s' AND `mapname` LIKE '%c%s%c' AND style = 0", g_szSteamID[client], PERCENT, szMapName, PERCENT);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectCPR - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_SelectCPRTimeCallback, szQuery, pack, DBPrio_Low);
}

public void SQL_SelectCPRTimeCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[surftimer] SQL Error (SQL_SelectCPRTimeCallback): %s", error);
		delete pack;
		return;
	}

	ResetPack(pack);
	int client = GetClientOfUserId(ReadPackCell(pack));

	if (IsValidClient(client))
	{
		if (results.HasResults && results.FetchRow())
		{
			results.FetchString(2, g_szCPRMapName[client], 128);
			g_fClientCPs[client][0] = results.FetchFloat(3);
			g_fClientVelsStart[client][0][0] = results.FetchInt(4);
			g_fClientVelsStart[client][0][1] = results.FetchInt(5);
			g_fClientVelsStart[client][0][2] = results.FetchInt(6);
			g_fClientVelsEnd[client][0][0] = results.FetchInt(7);
			g_fClientVelsEnd[client][0][1] = results.FetchInt(8);
			g_fClientVelsEnd[client][0][2] = results.FetchInt(9);

			char szQuery[512];
			Format(szQuery, sizeof(szQuery), "SELECT steamid, mapname, cp, time, velStartXY, velStartXYZ, velStartZ, velEndXY, velEndXYZ, velEndZ FROM ck_checkpoints WHERE steamid = '%s' AND mapname LIKE '%c%s%c' AND zonegroup = 0;", g_szSteamID[client], PERCENT, g_szCPRMapName[client], PERCENT);
			if (g_cLogQueries.BoolValue)
			{
				LogToFile(g_szQueryFile, "SQL_SelectCPRTimeCallback - szQuery: %s", szQuery);
			}
			g_dDb.Query(SQL_SelectCPRCallback, szQuery, pack, DBPrio_Low);
			return;
		}
		
		CPrintToChat(client, "%t", "SQLTwo7", g_szChatPrefix);
	}

	delete pack;
}

public void SQL_SelectCPRCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[surftimer] SQL Error (SQL_SelectCPRCallback): %s", error);
		delete pack;
		return;
	}

	if (results.HasResults && results.FetchRow())
	{
		ResetPack(pack);
		int client = ReadPackCell(pack);

		for (int i = 0; i <= 35; i++)
		{
			float fBuffer = 0.0;

			if (!results.IsFieldNull(i))
			{
				fBuffer = results.FetchFloat(i);
			}

			g_fClientCPs[client][i] = fBuffer;
		}
		db_selectCPRTarget(pack);

		return;
	}

	delete pack;
}

public void db_selectCPRTarget(DataPack pack)
{
	ResetPack(pack);
	int client = ReadPackCell(pack);
	int rank = ReadPackCell(pack);
	rank = rank - 1;

	char szQuery[512];
	if (rank == -1)
	{
		char szSteamId[32];
		ReadPackString(pack, szSteamId, 32);
		Format(szQuery, sizeof(szQuery), "SELECT `steamid`, `name`, `mapname`, `runtimepro` FROM `ck_playertimes` WHERE `mapname` LIKE '%c%s%c' AND steamid = '%s' AND style = 0", PERCENT, g_szCPRMapName[client], PERCENT, szSteamId);
	}
	else
		Format(szQuery, sizeof(szQuery), "SELECT `steamid`, `name`, `mapname`, `runtimepro` FROM `ck_playertimes` WHERE `mapname` LIKE '%c%s%c' AND style = 0 ORDER BY `runtimepro` ASC LIMIT %i, 1;", PERCENT, g_szCPRMapName[client], PERCENT, rank);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectCPRTarget - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_SelectCPRTargetCallback, szQuery, pack, DBPrio_Low);
}

public void SQL_SelectCPRTargetCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[surftimer] SQL Error (SQL_SelectCPRTargetCallback): %s", error);
		delete pack;
		return;
	}

	if (results.HasResults && results.FetchRow())
	{
		ResetPack(pack);
		int client = ReadPackCell(pack);

		char szSteamId[32];
		results.FetchString(0, szSteamId, sizeof(szSteamId));
		results.FetchString(1, g_szTargetCPR[client], sizeof(g_szTargetCPR));
		g_fTargetTime[client] = results.FetchFloat(3);
		g_fTargetVelsStart[client][0][0] = results.FetchInt(4);
		g_fTargetVelsStart[client][0][1] = results.FetchInt(5);
		g_fTargetVelsStart[client][0][2] = results.FetchInt(6);
		g_fTargetVelsEnd[client][0][0] = results.FetchInt(7);
		g_fTargetVelsEnd[client][0][1] = results.FetchInt(8);
		g_fTargetVelsEnd[client][0][2] = results.FetchInt(9); 
		db_selectCPRTargetCPs(szSteamId, pack);

		return;
	}

	delete pack;
}

public void db_selectCPRTargetCPs(const char[] szSteamId, DataPack pack)
{
	ResetPack(pack);
	int client = ReadPackCell(pack);

	char szQuery[512];
	Format(szQuery, sizeof(szQuery), "SELECT steamid, mapname, cp, time, velStartXY, velStartXYZ, velStartZ, velEndXY, velEndXYZ, velEndZ FROM ck_checkpoints WHERE steamid = '%s' AND mapname LIKE '%c%s%c' AND zonegroup = 0;", szSteamId, PERCENT, g_szCPRMapName[client], PERCENT);
	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_selectCPRTargetCPs - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_SelectCPRTargetCPsCallback, szQuery, pack, DBPrio_Low);
}

public void SQL_SelectCPRTargetCPsCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (!IsValidDatabase(db, error))
	{
		LogError("[surftimer] SQL Error (SQL_SelectCPRTargetCPsCallback): %s", error);
		delete pack;
		return;
	}

	if (results.HasResults)
	{
		ResetPack(pack);
		int client = ReadPackCell(pack);
		int rank = ReadPackCell(pack);

		Menu menu = CreateMenu(CPRMenuHandler);
		char szTitle[256], szName[MAX_NAME_LENGTH];
		GetClientName(client, szName, sizeof(szName));
		Format(szTitle, sizeof(szTitle), "%s VS %s on %s\n \n", szName, g_szTargetCPR[client], g_szCPRMapName[client], rank);
		SetMenuTitle(menu, szTitle);

		float targetCPs, comparedCPs;
		char szCPR[32], szCompared[32], szItem[256], szCompare[16];
		int i = 0;
		// int mode = g_SpeedMode[client];
		int mode = 1;
		int compareVel;

		while (results.FetchRow())
		{
			int cp = results.FetchInt(2);
			// g_fClientCPs[client][cp] = results.FetchFloat(3);
			g_fTargetVelsStart[client][cp][0] = results.FetchInt(4);
			g_fTargetVelsStart[client][cp][1] = results.FetchInt(5);
			g_fTargetVelsStart[client][cp][2] = results.FetchInt(6);
			g_fTargetVelsEnd[client][cp][0] = results.FetchInt(7);
			g_fTargetVelsEnd[client][cp][1] = results.FetchInt(8);
			g_fTargetVelsEnd[client][cp][2] = results.FetchInt(9);
			targetCPs = results.FetchFloat(3);
			comparedCPs = (g_fClientCPs[client][cp] - targetCPs);
			if (i == 0)
			{
				
				compareVel = g_fClientVelsStart[client][0][mode] - g_fTargetVelsStart[client][cp][mode];
				if (g_fClientVelsStart[client][0][mode] > g_fTargetVelsStart[client][cp][mode])
					Format(szCompare, sizeof(szCompare), "+%d", compareVel);
				else
					Format(szCompare, sizeof(szCompare), "%d", compareVel);

				Format(szItem, sizeof(szItem), "Map Start: 00:00:00 (00:00:00) | Start: %d u/s (%s u/s)", g_fClientVelsStart[client][0][mode], szCompare);
				AddMenuItem(menu, "", szItem, ITEMDRAW_DISABLED);
				i++;
			}

			if (targetCPs == 0.0 || g_fClientCPs[client][cp] == 0.0)
				continue;

			compareVel = g_fClientVelsEnd[client][cp][mode] - g_fTargetVelsEnd[client][cp][mode];
			if (g_fClientVelsEnd[client][cp][mode] > g_fTargetVelsEnd[client][cp][mode])
				Format(szCompare, sizeof(szCompare), "+%d", compareVel);
			else
				Format(szCompare, sizeof(szCompare), "%d", compareVel);

			FormatTimeFloat(client, targetCPs, 3, szCPR, sizeof(szCPR));
			FormatTimeFloat(client, comparedCPs, 6, szCompared, sizeof(szCompared));
			Format(szItem, sizeof(szItem), "CP %i: %s (%s) | Touch: %d u/s (%s u/s)", cp, szCPR, szCompared, g_fClientVelsEnd[client][cp][mode], szCompare);
			AddMenuItem(menu, "", szItem, ITEMDRAW_DISABLED);
		}

		char szTime[32], szCompared2[32];
		float compared = g_fClientCPs[client][0] - g_fTargetTime[client];
		FormatTimeFloat(client, g_fClientCPs[client][0], 3, szTime, sizeof(szTime));
		FormatTimeFloat(client, compared, 6, szCompared2, sizeof(szCompared2));
		compareVel = g_fClientVelsEnd[client][0][mode] - g_fTargetVelsEnd[client][0][mode];
		if (g_fClientVelsEnd[client][0][mode] > g_fTargetVelsEnd[client][0][mode])
			Format(szCompare, sizeof(szCompare), "+%d", compareVel);
		else
			Format(szCompare, sizeof(szCompare), "%d", compareVel);

		Format(szItem, sizeof(szItem), "Total Time: %s (%s) | End: %d u/s (%s u/s)", szTime, szCompared2, g_fClientVelsEnd[client][0][mode], szCompare);
		AddMenuItem(menu, "", szItem, ITEMDRAW_DISABLED);
		SetMenuOptionFlags(menu, MENUFLAG_BUTTON_EXIT);
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
	}

	delete pack;
}

public int CPRMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
		delete menu;
}

public void db_updateMapRankedStatus()
{
	char szQuery[256];
	if (g_bRankedMap)
	{
		Format(szQuery, sizeof(szQuery), "UPDATE ck_maptier SET ranked = 0 WHERE mapname = '%s';", g_szMapName);
		g_bRankedMap = false;
	}
	else
	{
		Format(szQuery, sizeof(szQuery), "UPDATE ck_maptier SET ranked = 1 WHERE mapname = '%s';", g_szMapName);
		g_bRankedMap = true;
	}

	if (g_cLogQueries.BoolValue)
	{
		LogToFile(g_szQueryFile, "db_updateMapRankedStatus - szQuery: %s", szQuery);
	}
	g_dDb.Query(SQL_CheckCallback, szQuery, _, DBPrio_Low);
}

public void sqlcreatePlayertimesIndex(Database db, DBResultSet results, const char[] error, any data)
{
	if (db == null || (strlen(error) && StrContains(error, "Duplicate", false) == -1))
	{
		SetFailState("[SurfTimer] (sqlcreatePlayertimesIndex) Can't add playertimes index. Error: %s", error);
		return;
	}
}

public void sqlcreateBonusIndex(Database db, DBResultSet results, const char[] error, any data)
{
	if (db == null || (strlen(error) && StrContains(error, "Duplicate", false) == -1))
	{
		SetFailState("[SurfTimer] (sqlcreateBonusIndex) Can't add bonus index. Error: %s", error);
		return;
	}
}

public void SQL_InsertAnnouncementCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (!IsValidDatabase(db, error))
	{
		if (StrContains(error, "Unknown column", false) != -1)
		{
			LogError("[Surftimer] (SQL_InsertAnnouncementCallback) Your database are not up to date! Please use the command \"sm_surftimer_upgrade\" to upgrade your database.");
		}
		else
		{
			LogError("[SurfTimer] SQL Error (SQL_InsertAnnouncementCallback): %s", error);
		}
		return;
	}
}
