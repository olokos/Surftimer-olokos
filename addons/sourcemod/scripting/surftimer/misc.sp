void setBotQuota()
{
	// Get bot_quota value
	ConVar hBotQuota = FindConVar("bot_quota");

	// Initialize
	SetConVarInt(hBotQuota, 0, false, false);

	// Check how many bots are needed
	int count = 0;
	if (g_bMapReplay[0])
		count++;
	if (GetConVarBool(g_hInfoBot))
		count++;
	if (g_BonusBotCount > 0)
		count++;
	if (GetConVarBool(g_hWrcpBot) && g_bhasStages && g_bFirstStageReplay)
		count++;

	if (count == 0)
		SetConVarInt(hBotQuota, 0, false, false);
	else
	{
		SetConVarInt(hBotQuota, count, false, false);
	}

	delete hBotQuota;

	return;
}

bool IsValidZonegroup(int zGrp)
{
	if (-1 < zGrp < g_mapZoneGroupCount)
		return true;
	return false;
}

/**
*	Checks if coordinates are inside a zone
*	Return: zone id where location is in, or -1 if not inside a zone
**/
int IsInsideZone (float location[3], float extraSize = 0.0)
{
	float tmpLocation[3];
	Array_Copy(location, tmpLocation, 3);
	tmpLocation[2] += 5.0;
	int iChecker;

	for (int i = 0; i < g_mapZonesCount; i++)
	{
		iChecker = 0;
		for(int x = 0; x < 3; x++)
		{
			if ((g_fZoneCorners[i][7][x] >= g_fZoneCorners[i][0][x] && (tmpLocation[x] <= (g_fZoneCorners[i][7][x] + extraSize) && tmpLocation[x] >= (g_fZoneCorners[i][0][x] - extraSize))) ||
			(g_fZoneCorners[i][0][x] >= g_fZoneCorners[i][7][x] && (tmpLocation[x] <= (g_fZoneCorners[i][0][x] + extraSize) && tmpLocation[x] >= (g_fZoneCorners[i][7][x] - extraSize))))
				iChecker++;
		}
		if (iChecker == 3)
			return i;
	}

	return -1;
}

public void loadAllClientSettings()
{
	for (int i = 1; i <= MAXPLAYERS; i++)
	{
		if (IsValidClient(i) && !IsFakeClient(i) && !g_bSettingsLoaded[i] && !g_bLoadingSettings[i])
		{
			g_iSettingToLoad[i] = 0;
			LoadClientSetting(i, 0);
			g_bLoadingSettings[i] = true;
		}
	}

	// RefreshZones();
	g_bServerDataLoaded = true;
}

public void LoadClientSetting(int client, int setting)
{
	if (IsValidClient(client) && !IsFakeClient(client))
	{
		if (StrContains(g_szSteamID[client], "STOP_IGNORING_RETVALS", false) != -1)
		{
			// Get SteamID
			if (!GetClientAuthId(client, AuthId_Steam2, g_szSteamID[client], MAX_NAME_LENGTH, true))
			{
				LogError("[SurfTimer] (LoadClientSetting) GetClientAuthId failed for client index %d.", client);
				return;
			}

			strcopy(g_pr_szSteamID[client], sizeof(g_pr_szSteamID[]), g_szSteamID[client]);
		}

		switch (setting)
		{
			case 0: db_viewPersonalRecords(client, g_szSteamID[client], g_szMapName);
			case 1: db_viewPersonalBonusRecords(client, g_szSteamID[client]);
			case 2: db_viewPersonalStageRecords(client, g_szSteamID[client]);
			case 3: db_viewPlayerPoints(client);
			case 4: db_viewPlayerOptions(client, g_szSteamID[client]);
			case 5: db_CheckVIPAdmin(client, g_szSteamID[client]);
			case 6: db_viewCustomTitles(client, g_szSteamID[client]);
			case 7: db_viewCheckpoints(client, g_szSteamID[client], g_szMapName);
			default: db_viewPersonalRecords(client, g_szSteamID[client], g_szMapName);
		}
		g_iSettingToLoad[client]++;
	}
}

public void getSteamIDFromClient(int client, char[] buffer, int length)
{
	// Get steamid - Points are being recalculated by an admin (pretty much going through top 20k players)
	if (client > MAXPLAYERS)
	{
		if (!g_pr_RankingRecalc_InProgress && !g_bProfileRecalc[client])
			return;
		Format(buffer, length, "%s", g_pr_szSteamID[client]);
	}
	else // Get steamid - Normal point increase
	{
		if (!GetConVarBool(g_hPointSystem) || !IsValidClient(client))
			return;
		GetClientAuthId(client, AuthId_Steam2, buffer, length, true);
	}
	return;
}

/*
Handles teleporting of players
Zonegroup: 0 = normal map, >0 bonuses.
Zone types: 1 = Start zone,  >1 Stage zones.
*/
public void teleportClient(int client, int zonegroup, int zone, bool stopTime)
{
	if (!IsValidClient(client))
		return;

	if (!IsValidZonegroup(zonegroup))
	{
		CPrintToChat(client, "%t", "Misc1", g_szChatPrefix);
		db_selectMapZones();
		return;
	}

	// Set Defaults

	// fluffys gravity
	ResetGravity(client);

	if (g_iInitalStyle[client] != 5 && g_iInitalStyle[client] != 6)
	 	SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.0);

	// Hack fix for b1 of surf_aircontrol_ksf
	if (StrEqual(g_szMapName, "surf_aircontrol_ksf_123") && zonegroup == 1)
		SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 2.0);

	if (g_bPracticeMode[client])
		Command_normalMode(client, 1);

	g_bNotTeleporting[client] = false;
	g_bInJump[client] = false;
	g_bFirstJump[client] = false;
	g_bLeftZone[client] = false;
	g_bInBhop[client] = false;
	g_iTicksOnGround[client] = 0;
	g_bNewStage[client] = false;

	// Check for spawn locations
	int realZone;
	if (zone < 0)
		realZone = 0;
	else
		realZone = zone;

	if (realZone > 1)
		g_bInStageZone[client] = true;
	else if (realZone == 1)
		g_bInStartZone[client] = true;

	// Check clients tele side
	int teleside = g_iTeleSide[client];

	int zoneID = getZoneID(zonegroup, zone);
	// Check if requested zone teleport is valid (non-linear map)
	if(zoneID == -1) {
		CPrintToChat(client, "Invalid stage or map has no stages!");
		return;
	}
	
	if (!StrEqual("player", g_mapZones[zoneID].TargetName))
		DispatchKeyValue(client, "targetname", g_mapZones[zoneID].TargetName);

	g_StageRecStartFrame[client] = -1;

	if (zone == 1 && g_bStartposUsed[client][zonegroup])
	{
		if (GetClientTeam(client) == 1 || GetClientTeam(client) == 0) // Spectating
		{
			if (stopTime)
				Client_Stop(client, 0);

			Array_Copy(g_fStartposLocation[client][zonegroup], g_fTeleLocation[client], 3);
			// Array_Copy(g_fSpawnLocation[zonegroup][realZone], g_fStartposLocation[client][zonegroup], 3);

			g_specToStage[client] = true;
			g_bRespawnPosition[client] = false;

			TeamChangeActual(client, 0);
			return;
		}
		else
		{
			SetEntPropVector(client, Prop_Data, "m_vecVelocity", view_as<float>( { 0.0, 0.0, 0.0 } ));

			// Hack fix for zoneid not being set with hooked zones
			int zId = getZoneID(zonegroup, zone);
			if (!StrEqual(g_mapZones[zId].HookName, "None"))
				g_iTeleportingZoneId[client] = zId;

			teleportEntitySafe(client, g_fStartposLocation[client][zonegroup], g_fStartposAngle[client][zonegroup], view_as<float>( { 0.0, 0.0, 0.0 } ), stopTime);

			return;
		}
	}
	else if (g_bGotSpawnLocation[zonegroup][realZone][teleside])
	{
		// Check if teleporting to bonus
		if (zonegroup > 0)
		{
			// Set a bool to allow bonus zones to sit on top of start zones, e.g surf_aircontrol_ksf bonus 1
			g_bInBonus[client] = true;
			g_iInBonus[client] = zonegroup;
		}
		else
		{
			// Not teleporting to a bonus
			g_bInBonus[client] = false;
		}

		if (GetClientTeam(client) == 1 || GetClientTeam(client) == 0) // Spectating
		{
			if (stopTime)
				Client_Stop(client, 0);

			Array_Copy(g_fSpawnLocation[zonegroup][realZone][teleside], g_fTeleLocation[client], 3);

			g_specToStage[client] = true;
			g_bRespawnPosition[client] = false;

			TeamChangeActual(client, 0);
			return;
		}
		else
		{
			SetEntPropVector(client, Prop_Data, "m_vecVelocity", view_as<float>( { 0.0, 0.0, 0.0 } ));

			// Hack fix for zoneid not being set with hooked zones
			int zId = getZoneID(zonegroup, zone);
			if (!StrEqual(g_mapZones[zId].HookName, "None"))
				g_iTeleportingZoneId[client] = zId;

			if (realZone == 0)
			{
				g_bInStartZone[client] = false;
				g_bInStageZone[client] = false;
			}

			teleportEntitySafe(client, g_fSpawnLocation[zonegroup][realZone][teleside], g_fSpawnAngle[zonegroup][realZone][teleside], g_fSpawnVelocity[zonegroup][realZone][teleside], stopTime);

			return;
		}
	}
	else
	{
		// Check if the map has zones
		if (g_mapZonesCount > 0)
		{
			// Search for the zoneid we're teleporting to:
			int destinationZoneId = getZoneID(zonegroup, zone);
			g_iTeleportingZoneId[client] = destinationZoneId;

			// Check if zone was found
			if (destinationZoneId > -1)
			{
				// Check if teleporting to bonus
				if (zonegroup > 0)
				{
					// Set a bool to allow bonus zones to sit on top of start zones, e.g surf_aircontrol_ksf bonus 1
					g_bInBonus[client] = true;
					g_iInBonus[client] = zonegroup;
				}
				else
				{
					// Not teleporting to a bonus
					g_bInBonus[client] = false;
				}
				// Check if client is spectating, or not chosen a team yet
				if (GetClientTeam(client) == 1 || GetClientTeam(client) == 0)
				{
					if (stopTime)
						Client_Stop(client, 0);

					// Set spawn location to the destination zone:
					Array_Copy(g_mapZones[destinationZoneId].CenterPoint, g_fTeleLocation[client], 3);

					// Set specToStage flag
					g_bRespawnPosition[client] = false;
					g_specToStage[client] = true;

					// Spawn player
					TeamChangeActual(client, 0);

					if (realZone == 0)
					{
						g_bInStartZone[client] =  false;
						g_bInStageZone[client] = false;
					}
				}
				else // Teleport normally
				{
					bool destinationFound = false;
					int entity;
					float origin[3];
					float ang[3];
					for (int i = 0; i < GetArraySize(g_hDestinations); i++)
					{
						entity = GetArrayCell(g_hDestinations, i);
						GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
						/**
						*	Checks if coordinates are inside a zone
						*	Return: zone id where location is in, or -1 if not inside a zone
						**/
						if (zonegroup > 0 && StrEqual(g_szMapName, "surf_mudkip_fix"))
						{
							char szBuffer[128];
							char szTargetName[128];
							GetEntPropString(entity, Prop_Send, "m_iName", szBuffer, sizeof(szBuffer));
							Format(szTargetName, 128, "bonus%i", zonegroup);
							if (zonegroup == 5)
								Format(szTargetName, 128, "%s_1", szTargetName);

							if (StrEqual(szBuffer, szTargetName))
							{
								destinationFound = true;
								GetEntPropVector(entity, Prop_Send, "m_angRotation", ang);
								break;
							}
						}
						else
						{
							if (IsInsideZone(origin) == destinationZoneId)
							{
								destinationFound = true;
								GetEntPropVector(entity, Prop_Send, "m_angRotation", ang);
								break;
							}
						}
					}

					// Set client speed to 0
					SetEntPropVector(client, Prop_Data, "m_vecVelocity", view_as<float>( { 0.0, 0.0, -100.0 } ));

					float fLocation[3];
					if (destinationFound)
						Array_Copy(origin, fLocation, 3);
					else
						Array_Copy(g_mapZones[destinationZoneId].CenterPoint, fLocation, 3);

					// fluffys dont cheat wrcps!
					g_bWrcpTimeractivated[client] = false;

					if (realZone == 0)
					{
						g_bInStartZone[client] =  false;
						g_bInStageZone[client] = false;
					}

					// Teleport
					if (destinationFound)
						teleportEntitySafe(client, fLocation, ang, view_as<float>( { 0.0, 0.0, -100.0 } ), stopTime);
					else
						teleportEntitySafe(client, fLocation, NULL_VECTOR, view_as<float>( { 0.0, 0.0, -100.0 } ), stopTime);
				}
			}
			else
				CPrintToChat(client, "%t", "Misc2", g_szChatPrefix);
		}
		else
			CPrintToChat(client, "%t", "Misc3", g_szChatPrefix);
	}
	g_bNotTeleporting[client] = true;
	return;
}

void teleportEntitySafe(int client, float fDestination[3], float fAngles[3], float fVelocity[3], bool stopTimer)
{
	if (stopTimer)
		Client_Stop(client, 1);

	int zId = setClientLocation(client, fDestination); // Set new location

	if (zId > -1 && g_bTimerRunning[client] && g_mapZones[zId].ZoneType == 2) // If teleporting to the end zone, stop timer
		Client_Stop(client, 0);

	// Teleport
	TeleportEntity(client, fDestination, fAngles, fVelocity);
}

int setClientLocation(int client, float fDestination[3])
{
	int zId = IsInsideZone(fDestination);

	// Hack fix for hooked zones setting the clients zone id to -1
	if (g_mapZonesCount > 0 && !StrEqual(g_mapZones[g_iTeleportingZoneId[client]].HookName, "None"))
	{
		// Any side effects from doing this? Not sure, I assume joni is getting a new zone id for a reason but I don't understand why when he gets the new zone id in the teleportClient function
		zId = g_iTeleportingZoneId[client];
	}

	if (zId != g_iClientInZone[client][3]) // Ignore location changes, if teleporting to the same zone they are already in
	{
		if (g_iClientInZone[client][0] != -1) // Ignore end touch if teleporting from within a zone
			g_bIgnoreZone[client] = true;

		if (zId > -1)
		{
			g_iClientInZone[client][0] = g_mapZones[zId].ZoneType;
			g_iClientInZone[client][1] = g_mapZones[zId].ZoneTypeId;
			g_iClientInZone[client][2] = g_mapZones[zId].ZoneGroup;
			g_iClientInZone[client][3] = zId;
		}
		else
		{
			g_iClientInZone[client][0] = -1;
			g_iClientInZone[client][1] = -1;
			g_iClientInZone[client][3] = -1;
		}
	}
	return zId;
}

stock void WriteChatLog(int client, const char[] sayOrSayTeam, const char[] msg)
{
	char name[MAX_NAME_LENGTH], steamid[32], teamName[10];

	GetClientName(client, name, MAX_NAME_LENGTH);
	GetTeamName(GetClientTeam(client), teamName, sizeof(teamName));
	GetClientAuthId(client, AuthId_Steam2, steamid, 32, true);
	LogToGame("\"%s<%i><%s><%s>\" %s \"%s\"", name, GetClientUserId(client), steamid, teamName, sayOrSayTeam, msg);
}

// PushFix by Mev, George, & Blacky
// https://forums.alliedmods.net/showthread.php?t=267131
public void SinCos(float radians, float &sine, float &cosine)
{
	sine = Sine(radians);
	cosine = Cosine(radians);
}

void DoPush(int entity, int other, float m_vecPushDir[3])
{
	if (0 < other <= MaxClients)
	{
		if (!DoesClientPassFilter(entity, other))
		{
			return;
		}

		float newVelocity[3], angRotation[3], fPushSpeed;

		fPushSpeed = GetEntPropFloat(entity, Prop_Data, "m_flSpeed");
		GetEntPropVector(entity, Prop_Data, "m_angRotation", angRotation);

		// Rotate vector according to world
		float sr, sp, sy, cr, cp, cy;
		float matrix[3][4];

		SinCos(DegToRad(angRotation[1]), sy, cy);
		SinCos(DegToRad(angRotation[0]), sp, cp);
		SinCos(DegToRad(angRotation[2]), sr, cr);

		matrix[0][0] = cp * cy;
		matrix[1][0] = cp * sy;
		matrix[2][0] = -sp;

		float crcy = cr * cy;
		float crsy = cr * sy;
		float srcy = sr * cy;
		float srsy = sr * sy;

		matrix[0][1] = sp * srcy - crsy;
		matrix[1][1] = sp * srsy + crcy;
		matrix[2][1] = sr * cp;

		matrix[0][2] = (sp * crcy + srsy);
		matrix[1][2] = (sp * crsy - srcy);
		matrix[2][2] = cr * cp;

		matrix[0][3] = angRotation[0];
		matrix[1][3] = angRotation[1];
		matrix[2][3] = angRotation[2];

		float vecAbsDir[3];
		vecAbsDir[0] = m_vecPushDir[0] * matrix[0][0] + m_vecPushDir[1] * matrix[0][1] + m_vecPushDir[2] * matrix[0][2];
		vecAbsDir[1] = m_vecPushDir[0] * matrix[1][0] + m_vecPushDir[1] * matrix[1][1] + m_vecPushDir[2] * matrix[1][2];
		vecAbsDir[2] = m_vecPushDir[0] * matrix[2][0] + m_vecPushDir[1] * matrix[2][1] + m_vecPushDir[2] * matrix[2][2];

		ScaleVector(vecAbsDir, fPushSpeed);

		// Apply the base velocity directly to abs velocity
		GetEntPropVector(other, Prop_Data, "m_vecVelocity", newVelocity);

		newVelocity[2] = newVelocity[2] + (vecAbsDir[2] * GetTickInterval());
		g_bPushing[other] = true;
		TeleportEntity(other, NULL_VECTOR, NULL_VECTOR, newVelocity);

		// Remove the base velocity z height so abs velocity can do it and add old base velocity if there is any
		vecAbsDir[2] = 0.0;
		if (GetEntityFlags(other) & FL_BASEVELOCITY)
		{
			float vecBaseVel[3];
			GetEntPropVector(other, Prop_Data, "m_vecBaseVelocity", vecBaseVel);
			AddVectors(vecAbsDir, vecBaseVel, vecAbsDir);
		}

		SetEntPropVector(other, Prop_Data, "m_vecBaseVelocity", vecAbsDir);
		SetEntityFlags(other, GetEntityFlags(other) | FL_BASEVELOCITY);
	}
}

void GetFilterTargetName(char[] filtername, char[] buffer, int maxlen)
{
	int filter = FindEntityByTargetname(filtername);
	if (filter != -1)
	{
		GetEntPropString(filter, Prop_Data, "m_iFilterName", buffer, maxlen);
	}
}

int FindEntityByTargetname(char[] targetname)
{
	int entity = -1;
	char sName[64];
	while ((entity = FindEntityByClassname(entity, "filter_activator_name")) != -1)
	{
		GetEntPropString(entity, Prop_Data, "m_iName", sName, 64);
		if (StrEqual(sName, targetname))
		{
			return entity;
		}
	}

	return -1;
}

bool DoesClientPassFilter(int entity, int client)
{
	char sPushFilter[64];
	GetEntPropString(entity, Prop_Data, "m_iFilterName", sPushFilter, sizeof sPushFilter);
	if (StrEqual(sPushFilter, ""))
	{
		return true;
	}
	char sFilterName[64];
	GetFilterTargetName(sPushFilter, sFilterName, sizeof sFilterName);
	char sClientName[64];
	GetEntPropString(client, Prop_Data, "m_iName", sClientName, sizeof sClientName);

	return StrEqual(sFilterName, sClientName, true);
}

// https://forums.alliedmods.net/showthread.php?t=206308
void TeamChangeActual(int client, int toteam)
{
	if (GetConVarBool(g_hForceCT)) {
		if (toteam == 0 || toteam == 2) {
			toteam = 3;
		}
	} else {
		if (toteam == 0) { // client is auto-assigning
			toteam = GetRandomInt(2, 3);
		}
	}

	if (g_bSpectate[client])
	{
		if (g_fStartTime[client] != -1.0 && g_bTimerRunning[client] == true)
			g_fPauseTime[client] = GetGameTime() - g_fStartPauseTime[client];
		g_bSpectate[client] = false;
	}

	ChangeClientTeam(client, toteam);

	return;
}

public int getZoneID(int zoneGrp, int stage)
{
	if (0 < stage < 2) // Search for map's starting zone
	{
		for (int i = 0; i < g_mapZonesCount; i++)
		{
			if (g_mapZones[i].ZoneGroup == zoneGrp && (g_mapZones[i].ZoneType == 1 || g_mapZones[i].ZoneType == 5) && g_mapZones[i].ZoneTypeId == 0)
				return i;
		}
		for (int i = 0; i < g_mapZonesCount; i++) // If no start zone with typeId 0 found, return any start zone
		{
			if (g_mapZones[i].ZoneGroup == zoneGrp && (g_mapZones[i].ZoneType == 1 || g_mapZones[i].ZoneType == 5))
				return i;
		}
	}
	else if (stage > 1) // Search for a stage
	{
		for (int i = 0; i < g_mapZonesCount; i++)
		{
			if (g_mapZones[i].ZoneGroup == zoneGrp && g_mapZones[i].ZoneType == 3 && g_mapZones[i].ZoneTypeId == (stage - 2))
			{
				return i;
			}
		}
	}
	else if (stage < 0) // Search for the end zone
	{
		for (int i = 0; i < g_mapZonesCount; i++)
		{
			if (g_mapZones[i].ZoneType == 2 && g_mapZones[i].ZoneGroup == zoneGrp)
			{
				return i;
			}
		}
	}
	return -1;
}

public void readMultiServerMapcycle()
{
	char sPath[PLATFORM_MAX_PATH];
	char line[128];

	ClearArray(g_MapList);
	g_pr_MapCount[0] = 0;
	BuildPath(Path_SM, sPath, sizeof(sPath), "%s", MULTI_SERVER_MAPCYCLE);
	Handle fileHandle = OpenFile(sPath, "r");

	if (fileHandle != null)
	{
		while (!IsEndOfFile(fileHandle) && ReadFileLine(fileHandle, line, sizeof(line)))
		{
			TrimString(line); // Only take the map name
			if (StrContains(line, "//", true) == -1) // Escape comments
			{
				g_pr_MapCount[0]++;
				PushArrayString(g_MapList, line);
	 		}
		}
	}
	else
		SetFailState("[surftimer] %s is empty or does not exist.", MULTI_SERVER_MAPCYCLE);

	delete fileHandle;

	return;
}

public void readMapycycle()
{
	char map[128];
	char map2[128];
	int mapListSerial = -1;
	g_pr_MapCount[0] = 0;
	if (ReadMapList(g_MapList,
			mapListSerial,
			"mapcyclefile",
			MAPLIST_FLAG_CLEARARRAY | MAPLIST_FLAG_NO_DEFAULT)
		 == null)
	{
		if (mapListSerial == -1)
		{
			SetFailState("[surftimer] mapcycle.txt is empty or does not exist.");
		}
	}
	for (int i = 0; i < GetArraySize(g_MapList); i++)
	{
		GetArrayString(g_MapList, i, map, sizeof(map));
		if (!StrEqual(map, "", false))
		{
			// fix workshop map name
			char mapPieces[6][128];
			int lastPiece = ExplodeString(map, "/", mapPieces, sizeof(mapPieces), sizeof(mapPieces[]));
			Format(map2, sizeof(map2), "%s", mapPieces[lastPiece - 1]);
			SetArrayString(g_MapList, i, map2);
			g_pr_MapCount[0]++;
		}
	}
	return;
}

public void setNameColor(char[] ClientName, int index, int size)
{
	switch (index)
	{
		case 0: // 1st Rank
			Format(ClientName, size, "%c%s", WHITE, ClientName);
		case 1:
			Format(ClientName, size, "%c%s", DARKRED, ClientName);
		case 2:
			Format(ClientName, size, "%c%s", GREEN, ClientName);
		case 3:
			Format(ClientName, size, "%c%s", LIMEGREEN, ClientName);
		case 4:
			Format(ClientName, size, "%c%s", BLUE, ClientName);
		case 5:
			Format(ClientName, size, "%c%s", LIGHTGREEN, ClientName);
		case 6:
			Format(ClientName, size, "%c%s", RED, ClientName);
		case 7:
			Format(ClientName, size, "%c%s", GRAY, ClientName);
		case 8:
			Format(ClientName, size, "%c%s", YELLOW, ClientName);
		case 9:
			Format(ClientName, size, "%c%s", LIGHTBLUE, ClientName);
		case 10:
			Format(ClientName, size, "%c%s", DARKBLUE, ClientName);
		case 11:
			Format(ClientName, size, "%c%s", PINK, ClientName);
		case 12:
			Format(ClientName, size, "%c%s", LIGHTRED, ClientName);
		case 13:
			Format(ClientName, size, "%c%s", PURPLE, ClientName);
		case 14:
			Format(ClientName, size, "%c%s", DARKGREY, ClientName);
		case 15:
			Format(ClientName, size, "%c%s", ORANGE, ClientName);
	}
}

public void setTextColor(char[] ClientText, int index, int size)
{
	switch (index)
	{
		case 0: // 1st Rank
			Format(ClientText, size, "%c%s", WHITE, ClientText);
		case 1:
			Format(ClientText, size, "%c%s", DARKRED, ClientText);
		case 2:
			Format(ClientText, size, "%c%s", GREEN, ClientText);
		case 3:
			Format(ClientText, size, "%c%s", LIMEGREEN, ClientText);
		case 4:
			Format(ClientText, size, "%c%s", BLUE, ClientText);
		case 5:
			Format(ClientText, size, "%c%s", LIGHTGREEN, ClientText);
		case 6:
			Format(ClientText, size, "%c%s", RED, ClientText);
		case 7:
			Format(ClientText, size, "%c%s", GRAY, ClientText);
		case 8:
			Format(ClientText, size, "%c%s", YELLOW, ClientText);
		case 9:
			Format(ClientText, size, "%c%s", LIGHTBLUE, ClientText);
		case 10:
			Format(ClientText, size, "%c%s", DARKBLUE, ClientText);
		case 11:
			Format(ClientText, size, "%c%s", PINK, ClientText);
		case 12:
			Format(ClientText, size, "%c%s", LIGHTRED, ClientText);
		case 13:
			Format(ClientText, size, "%c%s", PURPLE, ClientText);
		case 14:
			Format(ClientText, size, "%c%s", DARKGREY, ClientText);
		case 15:
			Format(ClientText, size, "%c%s", ORANGE, ClientText);
	}
}

public void parseColorsFromString(char[] ParseString, int size)
{
	ReplaceString(ParseString, size, "{default}", "", false);
	ReplaceString(ParseString, size, "{white}", "", false);
	ReplaceString(ParseString, size, "{darkred}", "", false);
	ReplaceString(ParseString, size, "{green}", "", false);
	ReplaceString(ParseString, size, "{lime}", "", false);
	ReplaceString(ParseString, size, "{blue}", "", false);
	ReplaceString(ParseString, size, "{lightgreen}", "", false);
	ReplaceString(ParseString, size, "{red}", "", false);
	ReplaceString(ParseString, size, "{grey}", "", false);
	ReplaceString(ParseString, size, "{gray}", "", false);
	ReplaceString(ParseString, size, "{yellow}", "", false);
	ReplaceString(ParseString, size, "{lightblue}", "", false);
	ReplaceString(ParseString, size, "{darkblue}", "", false);
	ReplaceString(ParseString, size, "{pink}", "", false);
	ReplaceString(ParseString, size, "{lightred}", "", false);
	ReplaceString(ParseString, size, "{purple}", "", false);
	ReplaceString(ParseString, size, "{darkgrey}", "", false);
	ReplaceString(ParseString, size, "{darkgray}", "", false);
	ReplaceString(ParseString, size, "{limegreen}", "", false);
	ReplaceString(ParseString, size, "{orange}", "", false);
	ReplaceString(ParseString, size, "{olive}", "", false);
}

public void checkSpawnPoints()
{
	int tEnt, ctEnt;

	if (FindEntityByClassname(ctEnt, "info_player_counterterrorist") == -1 || FindEntityByClassname(tEnt, "info_player_terrorist") == -1) // No proper zones were found, try to recreate
	{
		// Check if spawn point has been added to the database with !addspawn
		char szQuery[256];
		Format(szQuery, sizeof(szQuery), "SELECT pos_x, pos_y, pos_z, ang_x, ang_y, ang_z FROM ck_spawnlocations WHERE mapname = '%s' AND zonegroup = 0;", g_szMapName);

		DataPack pack = new DataPack();
		pack.WriteCell(EntIndexToEntRef(tEnt));
		pack.WriteCell(EntIndexToEntRef(ctEnt));
		if (g_cLogQueries.BoolValue)
		{
			LogToFile(g_szQueryFile, "checkSpawnPoints - szQuery: %s", szQuery);
		}
		g_dDb.Query(sqlSelectSpawnPoints, szQuery, pack, DBPrio_Low);
	}
}

public void sqlSelectSpawnPoints(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if (db == null || strlen(error))
	{
		LogError("[Surftimer] SQL Error (sqlSelectSpawnPoints): %s", error);
		delete pack;
		return;
	}

	pack.Reset();

	int tEnt = EntRefToEntIndex(pack.ReadCell());
	int ctEnt = EntRefToEntIndex(pack.ReadCell());

	delete pack;

	float fSpawnLocation[3], fSpawnAngle[3];

	if (results.HasResults)
	{
		if (results.FetchRow())
		{
			fSpawnLocation[0] = results.FetchFloat(0);
			fSpawnLocation[1] = results.FetchFloat(1);
			fSpawnLocation[2] = results.FetchFloat(2);
			fSpawnAngle[0] = results.FetchFloat(3);
			fSpawnAngle[1] = results.FetchFloat(4);
			fSpawnAngle[2] = results.FetchFloat(5);
		}
	}

	if (ctEnt == -1 || tEnt == -1)
	{
		if (fSpawnLocation[0] == 0.0 && fSpawnLocation[1] == 0.0 && fSpawnLocation[2] == 0.0) // No spawnpoint added to map with !addspawn, try to find spawns from map
		{
			PrintToServer("surftimer | No valid spawns found in the map.");
			int zoneEnt = -1;
			zoneEnt = FindEntityByClassname(zoneEnt, "info_player_teamspawn"); // CSS/TF spawn found

			if (zoneEnt != -1)
			{
				GetEntPropVector(zoneEnt, Prop_Data, "m_angRotation", fSpawnAngle);
				GetEntPropVector(zoneEnt, Prop_Send, "m_vecOrigin", fSpawnLocation);

				PrintToServer("surftimer | Found info_player_teamspawn in location %f, %f, %f", fSpawnLocation[0], fSpawnLocation[1], fSpawnLocation[2]);
			}
			else
			{
				zoneEnt = FindEntityByClassname(zoneEnt, "info_player_start"); // Random spawn
				if (zoneEnt != -1)
				{
					GetEntPropVector(zoneEnt, Prop_Data, "m_angRotation", fSpawnAngle);
					GetEntPropVector(zoneEnt, Prop_Send, "m_vecOrigin", fSpawnLocation);

					PrintToServer("surftimer | Found info_player_start in location %f, %f, %f", fSpawnLocation[0], fSpawnLocation[1], fSpawnLocation[2]);
				}
				else
				{
					PrintToServer("No valid spawn points found in the map! Record bots will not work. Try adding a spawn point with !addspawn");
					return;
				}
			}
		}

		// Start creating new spawnpoints
		int pointT, pointCT, count = 0;
		while (count < 64)
		{
			pointT = CreateEntityByName("info_player_terrorist");
			ActivateEntity(pointT);
			pointCT = CreateEntityByName("info_player_counterterrorist");
			ActivateEntity(pointCT);
			if (IsValidEntity(pointT) && IsValidEntity(pointCT) && DispatchSpawn(pointT) && DispatchSpawn(pointCT))
			{
				TeleportEntity(pointT, fSpawnLocation, fSpawnAngle, NULL_VECTOR);
				TeleportEntity(pointCT, fSpawnLocation, fSpawnAngle, NULL_VECTOR);
				count++;
			}
		}

		// Remove possiblt bad spawns
		char sClassName[128];
		for (int i = 0; i < GetMaxEntities(); i++)
		{
			if (IsValidEdict(i) && IsValidEntity(i) && GetEdictClassname(i, sClassName, sizeof(sClassName)))
			{
				if (StrEqual(sClassName, "info_player_start") || StrEqual(sClassName, "info_player_teamspawn"))
				{
					RemoveEntity(i);
				}
			}
		}
	}
	else // Valid spawns were found, check that there is enough of them
	{
		int ent, spawnpoint;
		ent = -1;
		while ((ent = FindEntityByClassname(ent, "info_player_terrorist")) != -1)
		{
			if (tEnt == 0)
			{
				GetEntPropVector(ent, Prop_Data, "m_angRotation", fSpawnAngle);
				GetEntPropVector(ent, Prop_Send, "m_vecOrigin", fSpawnLocation);
			}
			tEnt++;
		}
		while ((ent = FindEntityByClassname(ent, "info_player_counterterrorist")) != -1)
		{
			if (ctEnt == 0 && tEnt == 0)
			{
				GetEntPropVector(ent, Prop_Data, "m_angRotation", fSpawnAngle);
				GetEntPropVector(ent, Prop_Send, "m_vecOrigin", fSpawnLocation);
			}
			ctEnt++;
		}

		if (tEnt > 0 || ctEnt > 0)
		{
			if (tEnt < 64)
			{
				while (tEnt < 64)
				{
					spawnpoint = CreateEntityByName("info_player_terrorist");
					if (IsValidEntity(spawnpoint) && DispatchSpawn(spawnpoint))
					{
						ActivateEntity(spawnpoint);
						TeleportEntity(spawnpoint, fSpawnLocation, fSpawnAngle, NULL_VECTOR);
						tEnt++;
					}
				}
			}

			if (ctEnt < 64)
			{
				while (ctEnt < 64)
				{
					spawnpoint = CreateEntityByName("info_player_counterterrorist");
					if (IsValidEntity(spawnpoint) && DispatchSpawn(spawnpoint))
					{
						ActivateEntity(spawnpoint);
						TeleportEntity(spawnpoint, fSpawnLocation, fSpawnAngle, NULL_VECTOR);
						ctEnt++;
					}
				}
			}
		}
	}
}

public Action CallAdmin_OnDrawOwnReason(int client)
{
	g_bClientOwnReason[client] = true;
	return Plugin_Continue;
}

public bool checkSpam(int client)
{
	float time = GetGameTime();
	if (GetConVarFloat(g_hChatSpamFilter) == 0.0)
		return false;

	if (!IsValidClient(client) || (GetUserFlagBits(client) & ADMFLAG_ROOT) || (GetUserFlagBits(client) & ADMFLAG_GENERIC))
		return false;

	bool result = false;

	if (time - g_fLastChatMessage[client] < GetConVarFloat(g_hChatSpamFilter))
	{
		result = true;
		g_messages[client]++;
	}
	else
		g_messages[client] = 0;

	if (4 < g_messages[client] < 8)
		CPrintToChat(client, "%t", "Misc4", g_szChatPrefix);
	else
		if (g_messages[client] >= 8)
	{
		KickClient(client, "Kicked for spamming.");
		return true;
	}

	g_fLastChatMessage[client] = time;
	return result;
}

stock bool IsValidClient(int client)
{
	if (client > 0 && client <= MaxClients && IsClientInGame(client))
	{
		return true;
	}
	return false;
}

stock void FakePrecacheSound(const char[] szPath)
{
	AddToStringTable(FindStringTable("soundprecache"), szPath);
}

public Action BlockRadio(int client, const char[] command, int args)
{
	if (!GetConVarBool(g_hRadioCommands) && IsValidClient(client))
	{
		CPrintToChat(client, "%t", "RadioCommandsDisabled", g_szChatPrefix);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public void StringToUpper(char[] input)
{
	for (int i = 0; ; i++)
	{
		if (input[i] == '\0')
			return;
		input[i] = CharToUpper(input[i]);
	}
}

public void GetCountry(int client)
{
	if (client != 0)
	{
		if (!IsFakeClient(client))
		{
			char IP[16];
			char code2[3];
			GetClientIP(client, IP, 16);

			// COUNTRY
			GeoipCountry(IP, g_szCountry[client], 100);
			if (!strcmp(g_szCountry[client], NULL_STRING))
				Format(g_szCountry[client], 100, "Unknown", g_szCountry[client]);
			else
				if (StrContains(g_szCountry[client], "United", false) != -1 ||
				StrContains(g_szCountry[client], "Republic", false) != -1 ||
				StrContains(g_szCountry[client], "Federation", false) != -1 ||
				StrContains(g_szCountry[client], "Island", false) != -1 ||
				StrContains(g_szCountry[client], "Netherlands", false) != -1 ||
				StrContains(g_szCountry[client], "Isle", false) != -1 ||
				StrContains(g_szCountry[client], "Bahamas", false) != -1 ||
				StrContains(g_szCountry[client], "Maldives", false) != -1 ||
				StrContains(g_szCountry[client], "Philippines", false) != -1 ||
				StrContains(g_szCountry[client], "Vatican", false) != -1)
			{
				Format(g_szCountry[client], 100, "The %s", g_szCountry[client]);
			}
			// CODE
			if (GeoipCode2(IP, code2))
			{
				Format(g_szCountryCode[client], 16, "%s", code2);
			}
			else
				Format(g_szCountryCode[client], 16, "??");
		}
	}
}

stock void StripAllWeapons(int client)
{
	int iEnt;
	for (int i = 0; i <= 5; i++)
	{
		if (i != 2)
			while ((iEnt = GetPlayerWeaponSlot(client, i)) != -1)
		{
			RemovePlayerItem(client, iEnt);
			RemoveEntity(iEnt);
		}
	}
	if (GetPlayerWeaponSlot(client, 2) == -1)
		GivePlayerItem(client, "weapon_knife");
}

public void MovementCheck(int client)
{
	MoveType mt;
	mt = GetEntityMoveType(client);
	if (mt == MOVETYPE_FLYGRAVITY)
	{
		Client_Stop(client, 1);
	}
}

public void PlayButtonSound(int client)
{
	if (!GetConVarBool(g_hSoundEnabled))
		return;
	if (!g_bEnableQuakeSounds[client])
		return;
	// Players button sound
	if (!IsFakeClient(client))
	{
		char buffer[255];
		GetConVarString(g_hSoundPath, buffer, 255);
		Format(buffer, sizeof(buffer), "play %s", buffer);
		ClientCommand(client, buffer);
	}

	// Spectators button sound
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && !IsPlayerAlive(i))
		{
			int SpecMode = GetEntProp(i, Prop_Send, "m_iObserverMode");
			if (SpecMode == 4 || SpecMode == 5)
			{
				int Target = GetEntPropEnt(i, Prop_Send, "m_hObserverTarget");
				if (Target == client)
				{
					char szsound[255];
					GetConVarString(g_hSoundPath, szsound, 256);
					Format(szsound, sizeof(szsound), "play %s", szsound);
					ClientCommand(i, szsound);
				}
			}
		}
	}
}

public void FixPlayerName(int client)
{
	char szName[64];
	char szOldName[64];
	GetClientName(client, szName, 64);
	Format(szOldName, 64, "%s ", szName);
	ReplaceChar("'", "`", szName);
	if (!(StrEqual(szOldName, szName)))
	{
		SetClientInfo(client, "name", szName);
		SetEntPropString(client, Prop_Data, "m_szNetname", szName);
		SetClientName(client, szName);
	}
}

public void LimitSpeed(int client)
{
	/* Dont limit speed in these conditions:
	 * Practice mode
	 * No end zone in current zonegroup
	 * End Zone
	 * Checkpoint Zone
	 * Misc Zones
	*/
	if (!IsValidClient(client) || !IsPlayerAlive(client) || IsFakeClient(client) || g_bPracticeMode[client] || g_mapZonesTypeCount[g_iClientInZone[client][2]][2] == 0 || g_iClientInZone[client][3] < 0 || g_iClientInZone[client][0] == 2 || g_iClientInZone[client][0] == 4 || g_iClientInZone[client][0] >= 6 || GetConVarInt(g_hLimitSpeedType) == 1)
		return;

	float speedCap = 0.0, CurVelVec[3];
	speedCap = g_mapZones[g_iClientInZone[client][3]].PreSpeed;

	if (speedCap == 0.0)
		return;

	GetEntPropVector(client, Prop_Data, "m_vecVelocity", CurVelVec);

	if (CurVelVec[0] == 0.0)
		CurVelVec[0] = 1.0;
	if (CurVelVec[1] == 0.0)
		CurVelVec[1] = 1.0;
	if (CurVelVec[2] == 0.0)
		CurVelVec[2] = 1.0;

	float currentspeed = SquareRoot(Pow(CurVelVec[0], 2.0) + Pow(CurVelVec[1], 2.0));

	if (currentspeed > speedCap)
	{
		NormalizeVector(CurVelVec, CurVelVec);
		ScaleVector(CurVelVec, speedCap);
		TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, CurVelVec);
	}
}

public void LimitSpeedNew(int client)
{
	if (!IsValidClient(client) || !IsPlayerAlive(client) || IsFakeClient(client))
		return;

	if (g_mapZonesCount <= 0 || g_bPracticeMode[client] || g_mapZonesTypeCount[g_iClientInZone[client][2]][2] == 0 || g_iClientInZone[client][3] < 0 || g_iClientInZone[client][0] == 2 || g_iClientInZone[client][0] == 4 || g_iClientInZone[client][0] >= 6 || GetConVarInt(g_hLimitSpeedType) == 0 || g_iCurrentStyle[client] == 7)
		return;

	if (GetConVarInt(g_hLimitSpeedType) == 0 || !g_bInStartZone[client] && !g_bInStageZone[client])
		return;

	float speedCap = 0.0;
	speedCap = g_mapZones[g_iClientInZone[client][3]].PreSpeed;

	if (speedCap <= 0.0)
		return;

	if (g_bInStartZone[client] || g_bInStageZone[client])
	{
		if (GetEntityFlags(client) & FL_ONGROUND)
		{
			g_iTicksOnGround[client]++;
			if (g_iTicksOnGround[client] > 60)
			{
				g_bNewStage[client] = false;
				g_bLeftZone[client] = false;
				return;
			}
		}
	}

	float fVel[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", fVel);

	// Determine how much each vector must be scaled for the magnitude to equal the limit
	// Derived from Pythagorean theorem, where the hypotenuse represents the magnitude of velocity,
	// and the two legs represent the x and y velocity components.
    // As a side effect, velocity component signs are also handled.
	float scale = speedCap / SquareRoot( Pow(fVel[0], 2.0) + Pow(fVel[1], 2.0) );

	// A scale < 1 indicates a magnitude > limit
	if (scale < 1.0)
	{

		// Reduce each vector by the appropriate amount
		fVel[0] = fVel[0] * scale;
		fVel[1] = fVel[1] * scale;

		// Impart new velocity onto player
		if (g_bInBhop[client] || g_bLeftZone[client])
		{
			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fVel);
		}
	}
}

public void LimitMaxSpeed(int client, float fMaxSpeed)
{
	if (!IsValidClient(client) || !IsPlayerAlive(client) || IsFakeClient(client))
		return;

	float CurVelVec[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", CurVelVec);

	if (CurVelVec[0] == 0.0)
		CurVelVec[0] = 1.0;
	if (CurVelVec[1] == 0.0)
		CurVelVec[1] = 1.0;
	if (CurVelVec[2] == 0.0)
		CurVelVec[2] = 1.0;

	float currentspeed = SquareRoot(Pow(CurVelVec[0], 2.0) + Pow(CurVelVec[1], 2.0));

	if (currentspeed > fMaxSpeed)
	{
		if (CurVelVec[0] > fMaxSpeed)
			CurVelVec[0] = fMaxSpeed;
		if (CurVelVec[1] > fMaxSpeed)
			CurVelVec[1] = fMaxSpeed;
		if (CurVelVec[2] > fMaxSpeed)
			CurVelVec[2] = fMaxSpeed;

		NormalizeVector(CurVelVec, CurVelVec);
		ScaleVector(CurVelVec, fMaxSpeed);
		TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, CurVelVec);
	}
}

public void SetClientDefaults(int client)
{
	float GameTime = GetGameTime();
	g_fLastCommandBack[client] = GameTime;
	g_ClientSelectedZone[client] = -1;
	g_Editing[client] = 0;
	g_iSelectedTrigger[client] = -1;

	g_bClientRestarting[client] = false;
	g_fClientRestarting[client] = GameTime;
	g_fErrorMessage[client] = GameTime;
	g_bPushing[client] = false;

	g_bLoadingSettings[client] = false;
	g_bSettingsLoaded[client] = false;

	g_fLastDifferenceTime[client] = 0.0;

	g_flastClientUsp[client] = GameTime;

	g_ClientRenamingZone[client] = false;

	g_bNewReplay[client] = false;
	g_bNewBonus[client] = false;

	g_bFirstTimerStart[client] = true;
	g_pr_Calculating[client] = false;

	g_bTimerRunning[client] = false;
	g_specToStage[client] = false;
	g_bSpectate[client] = false;
	if (!g_bLateLoaded)
		g_bFirstTeamJoin[client] = true;
	g_bFirstSpawn[client] = true;
	g_bRecalcRankInProgess[client] = false;
	g_bPause[client] = false;
	g_bPositionRestored[client] = false;
	g_bRestorePositionMsg[client] = false;
	g_bRestorePosition[client] = false;
	g_bRespawnPosition[client] = false;
	g_bNoClip[client] = false;
	g_bOverlay[client] = false;
	g_bClientOwnReason[client] = false;
	g_AdminMenuLastPage[client] = 0;
	g_MenuLevel[client] = -1;
	g_AttackCounter[client] = 0;
	g_SpecTarget[client] = -1;

	for (int i = 0; i < MAX_STYLES; i++)
	{
		g_pr_points[client][i] = 0;
		g_PlayerRank[client][i] = 99999;
	}

	g_fCurrentRunTime[client] = -1.0;
	g_fPlayerCordsLastPosition[client] = view_as<float>( { 0.0, 0.0, 0.0 } );
	g_fLastChatMessage[client] = GetGameTime();
	g_fLastTimeNoClipUsed[client] = -1.0;
	g_fStartTime[client] = -1.0;
	g_fPlayerLastTime[client] = -1.0;
	g_fPauseTime[client] = 0.0;
	g_StyleMapRank[0][client] = 99999;
	g_OldStyleMapRank[0][client] = 99999;
	g_fProfileMenuLastQuery[client] = GameTime;
	Format(g_szPlayerPanelText[client], 512, "");
	Format(g_pr_rankname[client], 128, "");
	Format(g_pr_rankname_style[client], 32, "");
	g_PlayerChatRank[client] = -1;
	g_bValidRun[client] = false;
	g_fMaxPercCompleted[client] = 0.0;
	Format(g_szLastSRDifference[client], 64, "");
	Format(g_szLastPBDifference[client], 64, "");

	Format(g_szPersonalStyleRecord[0][client], 64, "");

	for (int x = 0; x < MAXZONEGROUPS; x++)
	{
		Format(g_szStylePersonalRecordBonus[0][x][client], 64, "-");
		g_bCheckpointsFound[x][client] = false;
		g_StyleMapRankBonus[0][x][client] = 9999999;
		g_Stage[x][client] = 0;
		for (int i = 0; i < CPLIMIT; i++)
		{
			g_fCheckpointTimesNew[x][client][i] = 0.0;
			g_fCheckpointTimesRecord[x][client][i] = 0.0;

			for (int k = 0; i < 3; i++)
			{
				g_iCheckpointVelsStartNew[x][client][i][k] = 0;
				g_iCheckpointVelsEndNew[x][client][i][k] = 0;
				g_iCheckpointVelsAvgNew[x][client][i][k] = 0;
				g_iCheckpointVelsStartRecord[x][client][i][k] = 0;
				g_iCheckpointVelsEndRecord[x][client][i][k] = 0;
				g_iCheckpointVelsAvgRecord[x][client][i][k] = 0;
			}
		}
	}

	// g_fLastPlayerCheckpoint[client] = GameTime;
	g_bCreatedTeleport[client] = false;
	g_bPracticeMode[client] = false;

	// Client Options
	g_bHide[client] = false;
	g_bShowSpecs[client] = true;
	g_bAutoBhopClient[client] = true;
	g_bHideChat[client] = false;
	g_bViewModel[client] = true;
	g_bCheckpointsEnabled[client] = true;
	g_bEnableQuakeSounds[client] = true;
	g_bTimerEnabled[client] = true;

	// Style Defaults
	g_iCurrentStyle[client] = 0;
	g_iInitalStyle[client] = 0;
	g_szInitalStyle[client] = "Normal";

	// Show Zones
	g_bShowZones[client] = false;

	// Text Colour
	g_bHasCustomTextColour[client] = false;

	// VIP
	g_bCheckCustomTitle[client] = false;
	g_bZoner[client] = false;

	// WRCP Replays
	g_bSavingWrcpReplay[client] = false;

	// Reset Bonus Bool
	g_bInBonus[client] = false;

	g_iCenterSpeedEnt[client] = -1;

	g_iPlayTimeAliveSession[client] = 0;
	g_iPlayTimeSpecSession[client] = 0;

	// Show Triggers
	g_bShowTriggers[client] = false;

	// Goose Start Pos
	for (int i = 0; i < MAXZONEGROUPS; i++)
		g_bStartposUsed[client][i] = false;

	// Save loc
	g_iLastSaveLocIdClient[client] = 0;
	g_fLastCheckpointMade[client] = 0.0;

	// surf_christmas2
	g_bUsingStageTeleport[client] = false;

	// Enforce Titles
	g_bEnforceTitle[client] = false;

	g_iWaitingForResponse[client] = -1;

	g_iMenuPosition[client] = 0;

	// Set default stage maybe
	for (int i = 0; i < MAXZONEGROUPS; i++)
		g_Stage[i][client] = 1;

	g_bInBhop[client] = false;
}

// Get Runtime
public void GetcurrentRunTime(int client)
{
	float fGetGameTime = GetGameTime();
	g_fCurrentRunTime[client] = fGetGameTime - g_fStartTime[client] - g_fPauseTime[client];

	if (g_bWrcpTimeractivated[client])
		g_fCurrentWrcpRunTime[client] = fGetGameTime - g_fStartWrcpTime[client];
}

public float GetSpeed(int client)
{
	float fVelocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", fVelocity);
	float speed;

	if (g_SpeedMode[client] == 0) // XY
		speed = SquareRoot(Pow(fVelocity[0], 2.0) + Pow(fVelocity[1], 2.0));
	else if (g_SpeedMode[client] == 1) // XYZ
		speed = SquareRoot(Pow(fVelocity[0], 2.0) + Pow(fVelocity[1], 2.0) + Pow(fVelocity[2], 2.0));
	else if (g_SpeedMode[client] == 2) // Z
		speed = fVelocity[2];
	else // XY default
		speed = SquareRoot(Pow(fVelocity[0], 2.0) + Pow(fVelocity[1], 2.0));

	return speed;
}

int GetAllSpeedTypes(int client)
{
	int speed[3];
	for (int i = 0; i < 3; i++)
		speed[i] = 0;

	if (!IsValidClient(client))
		return speed;

	float fVelocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", fVelocity);

	speed[0] = RoundToNearest(SquareRoot(Pow(fVelocity[0], 2.0) + Pow(fVelocity[1], 2.0))); // XY
	speed[1] = RoundToNearest(SquareRoot(Pow(fVelocity[0], 2.0) + Pow(fVelocity[1], 2.0) + Pow(fVelocity[2], 2.0))); // XYZ
	speed[2] = RoundToNearest(fVelocity[2]);

	return speed;
}

public void SetCashState()
{
	ServerCommand("mp_startmoney 0; mp_playercashawards 0; mp_teamcashawards 0");
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
			SetEntProp(i, Prop_Send, "m_iAccount", 0);
	}
}

public void PlayRecordSound(int iRecordtype)
{
	char buffer[PLATFORM_MAX_PATH];
	if (iRecordtype == 1)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsValidClient(i) && !IsFakeClient(i) && g_bEnableQuakeSounds[i] == true)
			{
				Format(buffer, sizeof(buffer), "play %s", g_szRelativeSoundPathWR);
				ClientCommand(i, buffer);
			}
		}
	}
	else if (iRecordtype == 2)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsValidClient(i) && !IsFakeClient(i) && g_bEnableQuakeSounds[i] == true)
			{
				Format(buffer, sizeof(buffer), "play %s", g_szRelativeSoundPathWR);
				ClientCommand(i, buffer);
			}
		}
	}
	else if (iRecordtype == 3) // top10
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsValidClient(i) && !IsFakeClient(i) && g_bEnableQuakeSounds[i] == true)
			{
				Format(buffer, sizeof(buffer), "play %s", g_szRelativeSoundPathTop);
				ClientCommand(i, buffer);
			}
		}
	}
	else if (iRecordtype == 4) // Discotime
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsValidClient(i) && !IsFakeClient(i) && g_bEnableQuakeSounds[i] == true)
			{
				Format(buffer, sizeof(buffer), "play %s", g_szRelativeSoundPathTop);
				ClientCommand(i, buffer);
			}
		}
	}
}

public void PlayUnstoppableSound(int client)
{
	char buffer[255];
	Format(buffer, sizeof(buffer), "play %s", g_szRelativeSoundPathPB);
	if (!IsFakeClient(client) && g_bEnableQuakeSounds[client])
	{
		ClientCommand(client, buffer);
	}
	
	// Spec Stop Sound
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && !IsPlayerAlive(i))
		{
			int SpecMode = GetEntProp(i, Prop_Send, "m_iObserverMode");
			if (SpecMode == 4 || SpecMode == 5)
			{
				int Target = GetEntPropEnt(i, Prop_Send, "m_hObserverTarget");
				if (Target == client && g_bEnableQuakeSounds[i])
				{
					ClientCommand(i, buffer);
				}
			}
		}
	}
}

public void PlayWRCPRecord(int iRecordtype)
{
	char buffer[255];
	if (iRecordtype == 1)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsValidClient(i) && !IsFakeClient(i) && g_bEnableQuakeSounds[i] == true)
			{
				Format(buffer, sizeof(buffer), "play %s", g_szRelativeSoundPathWRCP);
				ClientCommand(i, buffer);
			}
		}
	}
}

public void InitPrecache()
{
	char szBuffer[256];

	GetConVarString(g_hSoundPathWR, szBuffer, sizeof(szBuffer));
	AddFileToDownloadsTable(szBuffer);
	FakePrecacheSound(g_szRelativeSoundPathWR);

	GetConVarString(g_hSoundPathPB, szBuffer, sizeof(szBuffer));
	AddFileToDownloadsTable(szBuffer);
	FakePrecacheSound(g_szRelativeSoundPathPB);

	GetConVarString(g_hSoundPathTop, szBuffer, sizeof(szBuffer));
	AddFileToDownloadsTable(szBuffer);
	FakePrecacheSound(g_szRelativeSoundPathTop);

	GetConVarString(g_hSoundPathWRCP, szBuffer, sizeof(szBuffer));
	AddFileToDownloadsTable(szBuffer);
	FakePrecacheSound(g_szRelativeSoundPathWRCP);

	// Replay Player Model
	GetConVarString(g_hReplayBotPlayerModel, szBuffer, 256);
	AddFileToDownloadsTable(szBuffer);
	PrecacheModel(szBuffer, true);

	// Replay Arm Model
	GetConVarString(g_hReplayBotArmModel, szBuffer, 256);
	AddFileToDownloadsTable(szBuffer);
	PrecacheModel(szBuffer, true);

	// Player Arm Model
	GetConVarString(g_hArmModel, szBuffer, 256);
	AddFileToDownloadsTable(szBuffer);
	PrecacheModel(szBuffer, true);

	// Player Model
	GetConVarString(g_hPlayerModel, szBuffer, 256);
	AddFileToDownloadsTable(szBuffer);
	PrecacheModel(szBuffer, true);

	g_BeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt", true);
	g_HaloSprite = PrecacheModel("materials/sprites/halo.vmt", true);
	PrecacheModel(ZONE_MODEL);

	// Preache default arm models
	PrecacheModel("models/weapons/t_arms.mdl", true);
	PrecacheModel("models/weapons/ct_arms.mdl", true);
}


// thx to V952 https://forums.alliedmods.net/showthread.php?t=212886
stock int TraceClientViewEntity(int client)
{
	float m_vecOrigin[3];
	float m_angRotation[3];
	GetClientEyePosition(client, m_vecOrigin);
	GetClientEyeAngles(client, m_angRotation);
	Handle tr = TR_TraceRayFilterEx(m_vecOrigin, m_angRotation, MASK_VISIBLE, RayType_Infinite, TRDontHitSelf, client);
	int pEntity = -1;
	if (TR_DidHit(tr))
	{
		pEntity = TR_GetEntityIndex(tr);
		delete tr;
		return pEntity;
	}
	delete tr;
	return -1;
}

// thx to V952 https://forums.alliedmods.net/showthread.php?t=212886
public bool TRDontHitSelf(int entity, int mask, any data)
{
	if (entity == data)
		return false;
	return true;
}

public void PrintMapRecords(int client, int type)
{
	if (type == 0)
	{
		if (g_fRecordStyleMapTime[0] != 9999999.0)
			{
				CPrintToChat(client, "%t", "Misc5", g_szChatPrefix, g_szRecordStylePlayer[0], g_szRecordStyleMapTime[0], g_szMapName);
			}
	}
	else if (type == 99)
	{
	for (int i = 1; i <= g_mapZoneGroupCount; i++)
		{
			if (g_fStyleBonusFastest[0][i] != 9999999.0) // BONUS
			{
				CPrintToChat(client, "%t", "Misc6", g_szChatPrefix, g_szStyleBonusFastest[0][i], g_szStyleBonusFastestTime[0][i], g_szZoneGroupName[i], g_szMapName);
			}
		}
	}
	else if (type == 1) // sw
	{
		if (g_fRecordStyleMapTime[type] != 9999999.0)
		{
			CPrintToChat(client, "%t", "Misc7", g_szChatPrefix, g_szRecordStylePlayer[type], g_szRecordStyleMapTime[type], g_szMapName);
		}
	}
	else if (type == 2) // hsw
	{
		if (g_fRecordStyleMapTime[type] != 9999999.0)
		{
			CPrintToChat(client, "%t", "Misc8", g_szChatPrefix, g_szRecordStylePlayer[type], g_szRecordStyleMapTime[type], g_szMapName);
		}
	}
	else if (type == 3) // bw
	{
		if (g_fRecordStyleMapTime[type] != 9999999.0)
		{
			CPrintToChat(client, "%t", "Misc9", g_szChatPrefix, g_szRecordStylePlayer[type], g_szRecordStyleMapTime[type], g_szMapName);
		}
	}
	else if (type == 4) // low-gravity
	{
		if (g_fRecordStyleMapTime[type] != 9999999.0)
		{
			CPrintToChat(client, "%t", "Misc10", g_szChatPrefix, g_szRecordStylePlayer[type], g_szRecordStyleMapTime[type], g_szMapName);
		}
	}
	else if (type == 5) // slow motion
	{
		if (g_fRecordStyleMapTime[type] != 9999999.0)
		{
			CPrintToChat(client, "%t", "Misc11", g_szChatPrefix, g_szRecordStylePlayer[type], g_szRecordStyleMapTime[type], g_szMapName);
		}
	}
	else if (type == 6) // fast forward
	{
		if (g_fRecordStyleMapTime[type] != 9999999.0)
		{
			CPrintToChat(client, "%t", "Misc12", g_szChatPrefix, g_szRecordStylePlayer[type], g_szRecordStyleMapTime[type], g_szMapName);
		}
	}
	else if (type == 7) // Freestyle
	{
		if (g_fRecordStyleMapTime[type] != 9999999.0)
		{
			CPrintToChat(client, "%t", "MiscFreestyle", g_szChatPrefix, g_szRecordStylePlayer[type], g_szRecordStyleMapTime[type], g_szMapName);
		}
	}
	else if (type == 991) // bonus sideways
	{
		type = 1;
		for (int i = 1; i <= g_mapZoneGroupCount; i++)
		{
			if (g_fStyleBonusFastest[type][i] != 9999999.0) // BONUS
			{
				CPrintToChat(client, "%t", "Misc13", g_szChatPrefix, g_szStyleBonusFastest[type][i], g_szZoneGroupName[i], g_szStyleBonusFastestTime[type][i], g_szMapName);
			}
		}
	}
	else if (type == 992) // bonus half-sideways
	{
		type = 2;
		for (int i = 1; i <= g_mapZoneGroupCount; i++)
		{
			if (g_fStyleBonusFastest[type][i] != 9999999.0) // BONUS
			{
				CPrintToChat(client, "%t", "Misc14", g_szChatPrefix, g_szStyleBonusFastest[type][i], g_szZoneGroupName[i], g_szStyleBonusFastestTime[type][i], g_szMapName);
			}
		}
	}
	else if (type == 993) // bonus backwards
	{
		type = 3;
		for (int i = 1; i <= g_mapZoneGroupCount; i++)
		{
			if (g_fStyleBonusFastest[type][i] != 9999999.0) // BONUS
			{
				CPrintToChat(client, "%t", "Misc15", g_szChatPrefix, g_szStyleBonusFastest[type][i], g_szZoneGroupName[i], g_szStyleBonusFastestTime[type][i], g_szMapName);
			}
		}
	}
	else if (type == 994) // bonus low-gravity
	{
		type = 4;
		for (int i = 1; i <= g_mapZoneGroupCount; i++)
		{
			if (g_fStyleBonusFastest[type][i] != 9999999.0) // BONUS
			{
				CPrintToChat(client, "%t", "Misc16", g_szChatPrefix, g_szStyleBonusFastest[type][i], g_szZoneGroupName[i], g_szStyleBonusFastestTime[type][i], g_szMapName);
			}
		}
	}
	else if (type == 995) // bonus slow motion
	{
		type = 5;
		for (int i = 1; i <= g_mapZoneGroupCount; i++)
		{
			if (g_fStyleBonusFastest[type][i] != 9999999.0) // BONUS
			{
				CPrintToChat(client, "%t", "Misc17", g_szChatPrefix, g_szStyleBonusFastest[type][i], g_szZoneGroupName[i], g_szStyleBonusFastestTime[type][i], g_szMapName);
			}
		}
	}
	else if (type == 996) // bonus fast forward
	{
		type = 6;
		for (int i = 1; i <= g_mapZoneGroupCount; i++)
		{
			if (g_fStyleBonusFastest[type][i] != 9999999.0) // BONUS
			{
				CPrintToChat(client, "%t", "Misc18", g_szChatPrefix, g_szStyleBonusFastest[type][i], g_szZoneGroupName[i], g_szStyleBonusFastestTime[type][i], g_szMapName);
			}
		}
	}
	else if (type == 997) // bonus freestyle
	{
		type = 7;
		for (int i = 1; i <= g_mapZoneGroupCount; i++)
		{
			if (g_fStyleBonusFastest[type][i] != 9999999.0) // BONUS
			{
				CPrintToChat(client, "%t", "MiscFreestyleBonus", g_szChatPrefix, g_szStyleBonusFastest[type][i], g_szZoneGroupName[i], g_szStyleBonusFastestTime[type][i], g_szMapName);
			}
		}
	}
}

stock void MapFinishedMsgs(int client, int rankThisRun = 0)
{
	if (IsValidClient(client))
	{
		float RecordDiff, RecordDiff2;
		char szRecordDiff[32], szRecordDiff2[32], szName[MAX_NAME_LENGTH];
		GetClientName(client, szName, 128);
		int count = g_StyleMapTimesCount[0];

		if (rankThisRun == 0)
			rankThisRun = g_StyleMapRank[0][client];

		int rank = g_StyleMapRank[0][client];
		char szGroup[128];
		if (rank >= 11 && rank <= g_G1Top)
			Format(szGroup, 128, "%cGroup 1%c", DARKRED, WHITE);
		else if (rank >= g_G2Bot && rank <= g_G2Top)
			Format(szGroup, 128, "%cGroup 2%c", GREEN, WHITE);
		else if (rank >= g_G3Bot && rank <= g_G3Top)
			Format(szGroup, 128, "%cGroup 3%c", BLUE, WHITE);
		else if (rank >= g_G4Bot && rank <= g_G4Top)
			Format(szGroup, 128, "%cGroup 4%c", YELLOW, WHITE);
		else if (rank >= g_G5Bot && rank <= g_G5Top)
			Format(szGroup, 128, "%cGroup 5%c", GRAY, WHITE);
		else
			Format(szGroup, 128, "");

		// Map SR, time difference formatting 
		RecordDiff = g_fRecordStyleMapTime[0] - g_fFinalTime[client];
		FormatTimeFloat(client, RecordDiff, 3, szRecordDiff, 32);
		if (RecordDiff > 0.0)
		{
			Format(szRecordDiff, 32, "+%s", szRecordDiff);
		}
		else
		{
			Format(szRecordDiff, 32, "-%s", szRecordDiff);
		}
		
		// Player beat map SR, time difference formatting 
		RecordDiff2 = g_fOldRecordStyleMapTime[0] - g_fFinalTime[client];
		FormatTimeFloat(client, RecordDiff2, 3, szRecordDiff2, 32);
		if (RecordDiff2 > 0.0)
		{
			Format(szRecordDiff2, 32, "-%s", szRecordDiff2);
		}
		else
		{
			Format(szRecordDiff2, 32, "+%s", szRecordDiff2);
		}

		// Check that ck_chat_record_type matches and ck_min_rank_announce matches
		if ((GetConVarInt(g_hAnnounceRecord) == 0 ||
			(GetConVarInt(g_hAnnounceRecord) == 1 && g_bStyleMapPBRecord[0][client] || g_bStyleMapSRVRecord[0][client] || g_bStyleMapFirstRecord[0][client]) ||
			(GetConVarInt(g_hAnnounceRecord) == 2 && g_bStyleMapSRVRecord[0][client])) &&
			(rankThisRun <= GetConVarInt(g_hAnnounceRank) || GetConVarInt(g_hAnnounceRank) == 0))
		{
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsValidClient(i) && !IsFakeClient(i))
				{
					if (g_bStyleMapSRVRecord[0][client] && g_fFinalTime[client] == g_fOldRecordStyleMapTime[0]) // Player sets 1st Server Record
					{
						PlayRecordSound(2);
						
						CPrintToChat(i,"%t", "FirstMapRecord", g_szChatPrefix, szName);
						PrintToConsole(client, "Surftimer | %s set the map record!", szName);

						CPrintToChat(i,"%t", "MapFinished1", g_szChatPrefix, szName, g_szFinalTime[client]);
						PrintToConsole(client, "Surftimer | %s set a SR of %s", szName, g_szFinalTime[client]);
					}
					else if (g_bStyleMapSRVRecord[0][client]) // Player beat the Server Record
					{
						PlayRecordSound(2);								

						CPrintToChat(i,"%t", "NewMapRecord", g_szChatPrefix, szName);
						PrintToConsole(client, "Surftimer | %s beat the map record!", szName);
							
						CPrintToChat(i,"%t", "MapFinished2", g_szChatPrefix, szName, g_szFinalTime[client], szRecordDiff2, g_szTimeDifference[client], g_StyleMapRank[0][client], count);
						PrintToConsole(client, "Surftimer | %s finished in %s [SR %s | PB %s | Rank #%i/%i]", szName, g_szFinalTime[client], szRecordDiff2, g_szTimeDifference[client], g_StyleMapRank[0][client], count);					
					}						 
					else if (g_bStyleMapFirstRecord[0][client] && !g_bStyleMapSRVRecord[0][client]) // Player 1st time finishing map 	
					{
						if (szGroup[client] == 0) // No group available
						{	
							CPrintToChat(i,"%t", "MapFinished3", g_szChatPrefix, szName, g_szFinalTime[client], szRecordDiff, g_StyleMapRank[0][client], count);
							PrintToConsole(client, "Surftimer | %s set a PB of %s [SR %s | Rank #%i/%i]", szName, g_szFinalTime[client], szRecordDiff, g_StyleMapRank[0][client], count);
						}
						if (szGroup[client] > 0) // Group available
						{
							CPrintToChat(i,"%t", "MapFinished4", g_szChatPrefix, szName, g_szFinalTime[client], szRecordDiff, g_StyleMapRank[0][client], count, szGroup);
							PrintToConsole(client, "Surftimer | %s set a PB of %s [SR %s | Rank #%i/%i | %s]", szName, g_szFinalTime[client], szRecordDiff, g_StyleMapRank[0][client], count, szGroup);
						}
					}
					else if (g_bStyleMapPBRecord[0][client] && !g_bStyleMapSRVRecord[0][client]) // Player beat Personal Record
					{
						PlayUnstoppableSound(client);
						
						if (szGroup[client] == 0) // No group available
						{
							CPrintToChat(client, "%t", "MapFinished5",g_szChatPrefix, szName, g_szFinalTime[client], szRecordDiff, g_szTimeDifference[client], g_StyleMapRank[0][client], count);
							PrintToConsole(client, "Surftimer | %s finished in %s [SR %s | PB %s | Rank #%i/%i]", szName, g_szFinalTime[client], szRecordDiff, g_szTimeDifference[client], g_StyleMapRank[0][client], count);
						}
						if (szGroup[client] > 0) // Group available
						{
							CPrintToChat(client, "%t", "MapFinished6",g_szChatPrefix, szName, g_szFinalTime[client], szRecordDiff, g_szTimeDifference[client], g_StyleMapRank[0][client], count, szGroup);
							PrintToConsole(client, "Surftimer | %s finished in %s [SR %s | PB %s | Rank #%i/%i | %s]", szName, g_szFinalTime[client], szRecordDiff, g_szTimeDifference[client], g_StyleMapRank[0][client], count, szGroup);
						}
					}	
					else if (!g_bStyleMapSRVRecord[0][client] && !g_bStyleMapFirstRecord[0][client] && !g_bStyleMapPBRecord[0][client]) // Player did not beat Server Record nor finish for 1st time nor beat Personal Record
					{
						CPrintToChat(client, "%t", "MapFinished7", g_szChatPrefix, szName, g_szFinalTime[client], szRecordDiff, g_szTimeDifference[client], g_StyleMapRank[0][client], count);
						PrintToConsole(client, "Surftimer | %s finished in %s [SR %s | PB %s | Rank #%i/%i]", szName, g_szFinalTime[client], szRecordDiff, g_szTimeDifference[client], g_StyleMapRank[0][client], count);
					}	
					
				}
			}		
		}				
		else
		{// Print to own chat only
			if (IsValidClient(client) && !IsFakeClient(client))
			{
				if (g_bStyleMapSRVRecord[0][client] && g_fFinalTime[client] == g_fOldRecordStyleMapTime[0]) // Player sets 1st Server Record
				{
					PlayRecordSound(2);
					
					CPrintToChat(client,"%t", "FirstMapRecord", g_szChatPrefix, szName);
					PrintToConsole(client, "Surftimer | %s set the map record!", szName);

					CPrintToChat(client,"%t", "MapFinished1", g_szChatPrefix, szName, g_szFinalTime[client]);
					PrintToConsole(client, "Surftimer | %s set a SR of %s", szName, g_szFinalTime[client]);
				}
				else if (g_bStyleMapFirstRecord[0][client] && !g_bStyleMapSRVRecord[0][client]) // Player 1st time finishing map 	
				{
					if (szGroup[client] == 0) // No group available
					{	
						CPrintToChat(client,"%t", "MapFinished3", g_szChatPrefix, szName, g_szFinalTime[client], szRecordDiff, g_StyleMapRank[0][client], count);
						PrintToConsole(client, "Surftimer | %s set a PB of %s [SR %s | Rank #%i/%i]", szName, g_szFinalTime[client], szRecordDiff, g_StyleMapRank[0][client], count);
					}
					if (szGroup[client] > 0) // Group available
					{
						CPrintToChat(client,"%t", "MapFinished4", g_szChatPrefix, szName, g_szFinalTime[client], szRecordDiff, g_StyleMapRank[0][client], count, szGroup);
						PrintToConsole(client, "Surftimer | %s set a PB of %s [SR %s | Rank #%i/%i | %s]", szName, g_szFinalTime[client], szRecordDiff, g_StyleMapRank[0][client], count, szGroup);
					}
				}
				else if (g_bStyleMapPBRecord[0][client] && !g_bStyleMapSRVRecord[0][client]) // Player beat Personal Record
				{
					PlayUnstoppableSound(client);
					
					if (szGroup[client] == 0) // No group available
					{
						CPrintToChat(client, "%t", "MapFinished5",g_szChatPrefix, szName, g_szFinalTime[client], szRecordDiff, g_szTimeDifference[client], g_StyleMapRank[0][client], count);
						PrintToConsole(client, "Surftimer | %s finished in %s [SR %s | PB %s | Rank #%i/%i]", szName, g_szFinalTime[client], szRecordDiff, g_szTimeDifference[client], g_StyleMapRank[0][client], count);
					}
					if (szGroup[client] > 0) // Group available
					{
						CPrintToChat(client, "%t", "MapFinished6",g_szChatPrefix, szName, g_szFinalTime[client], szRecordDiff, g_szTimeDifference[client], g_StyleMapRank[0][client], count, szGroup);
						PrintToConsole(client, "Surftimer | %s finished in %s [SR %s | PB %s | Rank #%i/%i | %s]", szName, g_szFinalTime[client], szRecordDiff, g_szTimeDifference[client], g_StyleMapRank[0][client], count, szGroup);
					}	
				}
				else if (!g_bStyleMapSRVRecord[0][client] && !g_bStyleMapFirstRecord[0][client] && !g_bStyleMapPBRecord[0][client]) // Player did not beat Server Record nor finish for 1st time nor beat Personal Record
				{
					CPrintToChat(client, "%t", "MapFinished7", g_szChatPrefix, szName, g_szFinalTime[client], szRecordDiff, g_szTimeDifference[client], g_StyleMapRank[0][client], count);
					PrintToConsole(client, "Surftimer | %s finished in %s [SR %s | PB %s | Rank #%i/%i]", szName, g_szFinalTime[client], szRecordDiff, g_szTimeDifference[client], g_StyleMapRank[0][client], count);
				}
										
			}
		}					

		// Send Announcements
		if (g_bStyleMapSRVRecord[0][client])
		{
			if (GetConVarBool(g_hRecordAnnounce))
				db_insertAnnouncement(client, szName, g_szMapName, 0, g_szFinalTime[client], 0);
			char buffer[1024];
			GetConVarString(g_hRecordAnnounceDiscord, buffer, 1024);
			if (g_bDiscord && !StrEqual(buffer, ""))
				sendDiscordAnnouncement(szName, g_szMapName, g_szFinalTime[client], szRecordDiff2);
		}

		if (g_bTop10Time[client])
			PlayRecordSound(3);

		if (g_StyleMapRank[0][client] == 99999 && IsValidClient(client))
			CPrintToChat(client, "%t", "FailedSaveData", g_szChatPrefix);

		Handle pack;
		int style = 0;
		CreateDataTimer(1.0, UpdatePlayerProfile, pack, TIMER_FLAG_NO_MAPCHANGE);
		WritePackCell(pack, GetClientUserId(client));
		WritePackCell(pack, style);

		if (g_bStyleMapFirstRecord[0][client] || g_bStyleMapPBRecord[0][client] || g_bStyleMapSRVRecord[0][client])
			CheckMapRanks(client);

		/* Start function call */
		Call_StartForward(g_MapFinishForward);

		/* Push parameters one at a time */
		Call_PushCell(client);
		Call_PushFloat(g_fFinalTime[client]);
		Call_PushString(g_szFinalTime[client]);
		Call_PushCell(g_StyleMapRank[0][client]);
		Call_PushCell(count);

		/* Finish the call, get the result */
		Call_Finish();

	}
	// recalc avg
	db_CalcAvgRunTime();

	return;
}

stock void PrintChatBonus (int client, int zGroup, int rank = 0)
{
	if (!IsValidClient(client))
		return;

	float RecordDiff, RecordDiff2;
	char szRecordDiff[54], szRecordDiff2[54], szName[128];

	if (rank == 0)
		rank = g_StyleMapRankBonus[0][zGroup][client];
	
	// Bonus SR, time difference formatting 
	RecordDiff = g_fStyleBonusFastest[0][zGroup] - g_fFinalTime[client];
	FormatTimeFloat(client, RecordDiff, 3, szRecordDiff, 54);
	if (RecordDiff > 0.0)
	{
		Format(szRecordDiff, 54, "+%s", szRecordDiff);
	}
	else
	{
		Format(szRecordDiff, 54, "-%s", szRecordDiff);
	}
	
	// Player beat bonus SR, time difference formatting 
	RecordDiff2 = g_fStyleOldBonusRecordTime[0][zGroup] - g_fFinalTime[client];
	FormatTimeFloat(client, RecordDiff2, 3, szRecordDiff2, 54);
	if (RecordDiff2 > 0.0)
	{
		Format(szRecordDiff2, 54, "+%s", szRecordDiff2);
	}
	else
	{
		Format(szRecordDiff2, 54, "-%s", szRecordDiff2);
	
	}
	
	GetClientName(client, szName, 128);
	if ((GetConVarInt(g_hAnnounceRecord) == 0 ||
		(GetConVarInt(g_hAnnounceRecord) == 1 && g_bBonusSRVRecord[client] || g_bBonusPBRecord[client] || g_bBonusFirstRecord[client]) ||
		(GetConVarInt(g_hAnnounceRecord) == 2 && g_bBonusSRVRecord[client])) &&
		(rank <= GetConVarInt(g_hAnnounceRank) || GetConVarInt(g_hAnnounceRank) == 0))
	{
		if (g_bBonusSRVRecord[client] && g_fFinalTime[client] == g_fStyleOldBonusRecordTime[0][client]) // Player sets 1st bonus record
		{
			PlayRecordSound(2);

			CPrintToChatAll("%t", "FirstBonusRecord", g_szChatPrefix, szName, g_szZoneGroupName[zGroup]);
			PrintToConsole(client, "Surftimer | %s set the %s record!", szName, g_szZoneGroupName[zGroup]);

			CPrintToChatAll("%t", "BonusFinished1", g_szChatPrefix, szName, g_szZoneGroupName[zGroup], g_szFinalTime[client]);
			PrintToConsole(client, "Surftimer | %s set a %s SR of %s", szName, g_szZoneGroupName[zGroup], g_szFinalTime[client]);
		}
		else if (g_bBonusSRVRecord[client]) // Player beats bonus record
		{
			PlayRecordSound(2);

			CPrintToChatAll("%t", "NewBonusRecord", g_szChatPrefix, szName, g_szZoneGroupName[zGroup]);
			PrintToConsole(client, "Surftimer | %s beat the %s record!", szName, g_szZoneGroupName[zGroup]);
				
			CPrintToChatAll("%t", "BonusFinished2", g_szChatPrefix, szName, g_szZoneGroupName[zGroup], g_szFinalTime[client], szRecordDiff2, g_szBonusTimeDifference[client], g_StyleMapRankBonus[0][zGroup][client], g_iStyleBonusCount[0][zGroup]);
			PrintToConsole(client, "Surftimer | %s finished %s in %s [SR %s | PB %s | Rank #%i/%i]", szName, g_szZoneGroupName[zGroup], g_szFinalTime[client], szRecordDiff2, g_szBonusTimeDifference[client], g_StyleMapRankBonus[0][zGroup][client], g_iStyleBonusCount[0][zGroup]);
		}
		else if (g_bBonusFirstRecord[client] && !g_bBonusSRVRecord[client]) // Player 1st time finishing bonus
		{
			CPrintToChatAll("%t", "BonusFinished3", g_szChatPrefix, szName, g_szZoneGroupName[zGroup], g_szFinalTime[client], szRecordDiff, g_StyleMapRankBonus[0][zGroup][client], g_iStyleBonusCount[0][zGroup]);
			PrintToConsole(client, "Surftimer | %s set a %s PB of %s [SR %s | Rank #%i/%i]", szName, g_szZoneGroupName[zGroup], g_szFinalTime[client], szRecordDiff, g_StyleMapRankBonus[0][zGroup][client], g_iStyleBonusCount[0][zGroup]);
		}
		else if (g_bBonusPBRecord[client] && !g_bBonusSRVRecord[client]) // Player beats PB but not bonus record
		{
			PlayUnstoppableSound(client);
			
			CPrintToChatAll("%t", "BonusFinished5", g_szChatPrefix, szName, g_szZoneGroupName[zGroup], g_szFinalTime[client], szRecordDiff, g_szBonusTimeDifference[client], g_StyleMapRankBonus[0][zGroup][client], g_iStyleBonusCount[0][zGroup]);
			PrintToConsole(client, "Surftimer | %s finished %s in %s [SR %s | PB %s | Rank #%i/%i]", szName, g_szZoneGroupName[zGroup], g_szFinalTime[client], szRecordDiff, g_szBonusTimeDifference[client], g_StyleMapRankBonus[0][zGroup][client], g_iStyleBonusCount[0][zGroup]);
		}
		else if (!g_bBonusSRVRecord[client] && !g_bBonusFirstRecord[client] && !g_bBonusPBRecord[client]) // Player did not beat bonus record nor set 1st bonus time nor beat bonus PB
		{
			CPrintToChatAll("%t", "BonusFinished6", g_szChatPrefix, szName, g_szZoneGroupName[zGroup], g_szFinalTime[client], szRecordDiff, g_szBonusTimeDifference[client], g_StyleMapRankBonus[0][zGroup][client], g_iStyleBonusCount[0][zGroup]);
			PrintToConsole(client, "Surftimer | %s finished %s in %s [SR %s | PB %s | Rank #%i/%i]", szName, g_szZoneGroupName[zGroup], g_szFinalTime[client], szRecordDiff, g_szBonusTimeDifference[client], g_StyleMapRankBonus[0][zGroup][client], g_iStyleBonusCount[0][zGroup]);
		}
	}
	else
	{
		if (g_bBonusSRVRecord[client] && g_fFinalTime[client] == g_fStyleOldBonusRecordTime[0][client]) // Player sets 1st bonus record
		{
			PlayRecordSound(2);

			CPrintToChat(client, "%t", "FirstBonusRecord", g_szChatPrefix, szName, g_szZoneGroupName[zGroup]);
			PrintToConsole(client, "Surftimer | %s set the %s record!", szName, g_szZoneGroupName[zGroup]);

			CPrintToChat(client, "%t", "BonusFinished1", g_szChatPrefix, szName, g_szZoneGroupName[zGroup], g_szFinalTime[client]);
			PrintToConsole(client, "Surftimer | %s set a %s SR of %s", szName, g_szZoneGroupName[zGroup], g_szFinalTime[client]);
		}
		else if (g_bBonusSRVRecord[client]) // Player beats bonus record
		{
			PlayRecordSound(2);

			CPrintToChat(client, "%t", "NewBonusRecord", g_szChatPrefix, szName, g_szZoneGroupName[zGroup]);
			PrintToConsole(client, "Surftimer | %s beat the %s record!", szName, g_szZoneGroupName[zGroup]);
				
			CPrintToChat(client, "%t", "BonusFinished2", g_szChatPrefix, szName, g_szZoneGroupName[zGroup], g_szFinalTime[client], szRecordDiff2, g_szBonusTimeDifference[client], g_StyleMapRankBonus[0][zGroup][client], g_iStyleBonusCount[0][zGroup]);
			PrintToConsole(client, "Surftimer | %s finished %s in %s [SR %s | PB %s | Rank #%i/%i]", szName, g_szZoneGroupName[zGroup], g_szFinalTime[client], szRecordDiff2, g_szBonusTimeDifference[client], g_StyleMapRankBonus[0][zGroup][client], g_iStyleBonusCount[0][zGroup]);
		}
		else if (g_bBonusFirstRecord[client] && !g_bBonusSRVRecord[client]) // Player 1st time finishing bonus
		{
			CPrintToChat(client, "%t", "BonusFinished3", g_szChatPrefix, szName, g_szZoneGroupName[zGroup], g_szFinalTime[client], szRecordDiff, g_StyleMapRankBonus[0][zGroup][client], g_iStyleBonusCount[0][zGroup]);
			PrintToConsole(client, "Surftimer | %s finished %s in %s [SR %s | Rank #%i/%i]", szName, g_szZoneGroupName[zGroup], g_szFinalTime[client], szRecordDiff, g_StyleMapRankBonus[0][zGroup][client], g_iStyleBonusCount[0][zGroup]);
		}
		else if (g_bBonusPBRecord[client] && !g_bBonusSRVRecord[client]) // Player beats PB but not bonus record
		{
			PlayUnstoppableSound(client);
			
			CPrintToChat(client, "%t", "BonusFinished5", g_szChatPrefix, szName, g_szZoneGroupName[zGroup], g_szFinalTime[client], szRecordDiff, g_szBonusTimeDifference[client], g_StyleMapRankBonus[0][zGroup][client], g_iStyleBonusCount[0][zGroup]);
			PrintToConsole(client, "Surftimer | %s finished %s in %s [SR %s | PB %s | Rank #%i/%i]", szName, g_szZoneGroupName[zGroup], g_szFinalTime[client], szRecordDiff, g_szBonusTimeDifference[client], g_StyleMapRankBonus[0][zGroup][client], g_iStyleBonusCount[0][zGroup]);
		}
		else if (!g_bBonusSRVRecord[client] && !g_bBonusFirstRecord[client] && !g_bBonusPBRecord[client]) // Player did not beat bonus record nor set 1st bonus time nor beat bonus PB
		{
			CPrintToChat(client, "%t", "BonusFinished6", g_szChatPrefix, szName, g_szZoneGroupName[zGroup], g_szFinalTime[client], szRecordDiff, g_szBonusTimeDifference[client], g_StyleMapRankBonus[0][zGroup][client], g_iStyleBonusCount[0][zGroup]);
			PrintToConsole(client, "Surftimer | %s finished %s in %s [SR %s | PB %s | Rank #%i/%i]", szName, g_szZoneGroupName[zGroup], g_szFinalTime[client], szRecordDiff, g_szBonusTimeDifference[client], g_StyleMapRankBonus[0][zGroup][client], g_iStyleBonusCount[0][zGroup]);
		}
	}

	// Send Announcements
	if (g_bBonusSRVRecord[client])
	{
		if (GetConVarBool(g_hRecordAnnounce))
			db_insertAnnouncement(client, szName, g_szMapName, 1, g_szFinalTime[client], zGroup);
		char buffer[1024], buffer1[1024];
		GetConVarString(g_hRecordAnnounceDiscord, buffer, 1024);
		GetConVarString(g_hRecordAnnounceDiscordBonus, buffer1, 1024);
		if (g_bDiscord && !StrEqual(buffer, "") && !StrEqual(buffer1, ""))
			sendDiscordAnnouncementBonus(szName, g_szMapName, g_szFinalTime[client], zGroup, szRecordDiff2);
	}

	/* Start function call */
	Call_StartForward(g_BonusFinishForward);

	/* Push parameters one at a time */
	Call_PushCell(client);
	Call_PushFloat(g_fFinalTime[client]);
	Call_PushString(g_szFinalTime[client]);
	Call_PushCell(rank);
	Call_PushCell(g_iStyleBonusCount[0][zGroup]);
	Call_PushCell(zGroup);

	/* Finish the call, get the result */
	Call_Finish();

	CheckBonusRanks(client, zGroup);
	db_CalcAvgRunTimeBonus();

	if (rank == 9999999 && IsValidClient(client))
		CPrintToChat(client, "%t", "FailedSaveData", g_szChatPrefix);

	return;
}

public void CheckMapRanks(int client)
{
	// if client has risen in rank,
	if (g_OldStyleMapRank[0][client] > g_StyleMapRank[0][client])
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsValidClient(i) && !IsFakeClient(i) && i != client)
			{ // if clients rank used to be bigger than i's, 2nd: clients new rank is at least as big as i's
				if (g_OldStyleMapRank[0][client] > g_StyleMapRank[0][i] && g_StyleMapRank[0][client] <= g_StyleMapRank[0][i])
					g_StyleMapRank[0][i]++;
			}
		}
	}
}

public void CheckBonusRanks(int client, int zGroup)
{
	// if client has risen in rank,
	if (g_StyleOldMapRankBonus[0][zGroup][client] > g_StyleMapRankBonus[0][zGroup][client])
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsValidClient(i) && !IsFakeClient(i) && i != client)
			{ // if clients rank used to be bigger than i's, 2nd: clients new rank is at least as big as i's
				if (g_StyleOldMapRankBonus[0][zGroup][client] > g_StyleMapRankBonus[0][zGroup][i] && g_StyleMapRankBonus[0][zGroup][client] <= g_StyleMapRankBonus[0][zGroup][i])
					g_StyleMapRankBonus[0][zGroup][i]++;
			}
		}
	}
}

public void ReplaceChar(char[] sSplitChar, char[] sReplace, char sString[64])
{
	StrCat(sString, sizeof(sString), " ");
	char sBuffer[16][256];
	ExplodeString(sString, sSplitChar, sBuffer, sizeof(sBuffer), sizeof(sBuffer[]));
	strcopy(sString, sizeof(sString), "");
	for (int i = 0; i < sizeof(sBuffer); i++)
	{
		if (strcmp(sBuffer[i], "") == 0)
			continue;
		if (i != 0)
		{
			char sTmpStr[256];
			Format(sTmpStr, sizeof(sTmpStr), "%s%s", sReplace, sBuffer[i]);
			StrCat(sString, sizeof(sString), sTmpStr);
		}
		else
		{
			StrCat(sString, sizeof(sString), sBuffer[i]);
		}
	}
}

public void FormatTimeFloat(int client, float time, int type, char[] string, int length)
{
	char szMilli[16];
	char szSeconds[16];
	char szMinutes[16];
	char szHours[16];
	char szMilli2[16];
	char szSeconds2[16];
	char szMinutes2[16];
	int imilli;
	int imilli2;
	int iseconds;
	int iminutes;
	int ihours;
	if (type != 6)
		time = FloatAbs(time);
	imilli = RoundToZero(time * 100);
	imilli2 = RoundToZero(time * 10);
	imilli = imilli % 100;
	imilli2 = imilli2 % 10;
	iseconds = RoundToZero(time);
	iseconds = iseconds % 60;
	iminutes = RoundToZero(time / 60);
	iminutes = iminutes % 60;
	ihours = RoundToZero((time / 60) / 60);

	if (imilli < 10)
		Format(szMilli, 16, "0%dms", imilli);
	else
		Format(szMilli, 16, "%dms", imilli);
	if (iseconds < 10)
		Format(szSeconds, 16, "0%ds", iseconds);
	else
		Format(szSeconds, 16, "%ds", iseconds);
	if (iminutes < 10)
		Format(szMinutes, 16, "0%dm", iminutes);
	else
		Format(szMinutes, 16, "%dm", iminutes);

	Format(szMilli2, 16, "%d", imilli2);
	if (iseconds < 10)
		Format(szSeconds2, 16, "0%d", iseconds);
	else
		Format(szSeconds2, 16, "%d", iseconds);
	if (iminutes < 10)
		Format(szMinutes2, 16, "0%d", iminutes);
	else
		Format(szMinutes2, 16, "%d", iminutes);
	// Time: 00m 00s 00ms
	if (type == 0)
	{
		Format(szHours, 16, "%dm", iminutes);
		if (ihours > 0)
		{
			Format(szHours, 16, "%d", ihours);
			Format(string, length, "%s:%s:%s.%s", szHours, szMinutes2, szSeconds2, szMilli2);
		}
		else
		{
			Format(string, length, "%s:%s.%s", szMinutes2, szSeconds2, szMilli2);
		}
	}
	// 00m 00s 00ms
	if (type == 1)
	{
		Format(szHours, 16, "%dm", iminutes);
		if (ihours > 0)
		{
			Format(szHours, 16, "%dh", ihours);
			Format(string, length, "%s %s %s %s", szHours, szMinutes, szSeconds, szMilli);
		}
		else
			Format(string, length, "%s %s %s", szMinutes, szSeconds, szMilli);
	}
	else
	// 00h 00m 00s 00ms
	if (type == 2)
	{
		imilli = RoundToZero(time * 1000);
		imilli = imilli % 1000;
		if (imilli < 10)
			Format(szMilli, 16, "00%dms", imilli);
		else
			if (imilli < 100)
				Format(szMilli, 16, "0%dms", imilli);
			else
				Format(szMilli, 16, "%dms", imilli);
		Format(szHours, 16, "%dh", ihours);
		Format(string, 32, "%s %s %s %s", szHours, szMinutes, szSeconds, szMilli);
	}
	else
	// 00:00:00
	if (type == 3)
	{
		if (imilli < 10)
			Format(szMilli, 16, "0%d", imilli);
		else
			Format(szMilli, 16, "%d", imilli);
		if (iseconds < 10)
			Format(szSeconds, 16, "0%d", iseconds);
		else
			Format(szSeconds, 16, "%d", iseconds);
		if (iminutes < 10)
			Format(szMinutes, 16, "0%d", iminutes);
		else
			Format(szMinutes, 16, "%d", iminutes);
		if (ihours > 0)
		{
			Format(szHours, 16, "%d", ihours);
			Format(string, length, "%s:%s:%s:%s", szHours, szMinutes, szSeconds, szMilli);
		}
		else
			Format(string, length, "%s:%s:%s", szMinutes, szSeconds, szMilli);
	}
	// Time: 00:00:00
	if (type == 4)
	{
		if (imilli < 10)
			Format(szMilli, 16, "0%d", imilli);
		else
			Format(szMilli, 16, "%d", imilli);
		if (iseconds < 10)
			Format(szSeconds, 16, "0%d", iseconds);
		else
			Format(szSeconds, 16, "%d", iseconds);
		if (iminutes < 10)
			Format(szMinutes, 16, "0%d", iminutes);
		else
			Format(szMinutes, 16, "%d", iminutes);
		if (ihours > 0)
		{
			Format(szHours, 16, "%d", ihours);
			Format(string, length, "Time: %s:%s:%s", szHours, szMinutes, szSeconds);
		}
		else
			Format(string, length, "Time: %s:%s", szMinutes, szSeconds);
	}
	// goes to  00:00
	if (type == 5)
	{
		if (imilli < 10)
			Format(szMilli, 16, "0%d", imilli);
		else
			Format(szMilli, 16, "%d", imilli);
		if (iseconds < 10)
			Format(szSeconds, 16, "0%d", iseconds);
		else
			Format(szSeconds, 16, "%d", iseconds);
		if (iminutes < 10)
			Format(szMinutes, 16, "0%d", iminutes);
		else
			Format(szMinutes, 16, "%d", iminutes);
		if (ihours > 0)
		{

			Format(szHours, 16, "%d", ihours);
			Format(string, length, "%s:%s:%s:%s", szHours, szMinutes, szSeconds, szMilli);
		}
		else
			if (iminutes > 0)
				Format(string, length, "%s:%s:%s", szMinutes, szSeconds, szMilli);
			else
				Format(string, length, "%s:%ss", szSeconds, szMilli);
	}
	// +-00:00:00
	if (type == 6)
	{
		if (imilli < 10)
			Format(szMilli, 16, "0%d", imilli);
		else
			Format(szMilli, 16, "%d", imilli);
		if (iseconds < 10)
			Format(szSeconds, 16, "0%d", iseconds);
		else
			Format(szSeconds, 16, "%d", iseconds);
		if (iminutes < 10)
			Format(szMinutes, 16, "0%d", iminutes);
		else
			Format(szMinutes, 16, "%d", iminutes);
		if (ihours > 0)
		{
			Format(szHours, 16, "%d", ihours);
			Format(string, length, "%s:%s:%s:%s", szHours, szMinutes, szSeconds, szMilli);
		}
		else
			Format(string, length, "%s:%s:%s", szMinutes, szSeconds, szMilli);

		ReplaceString(string, length, "-", "");

		if (time > 0.0)
			Format(string, length, "+%s", string);
		else
			Format(string, length, "-%s", string);
	}
}

public void SetSkillGroups()
{
	// Map Points
	int mapcount;
	if (g_pr_MapCount[0] < 1)
		mapcount = 1;
	else
		mapcount = g_pr_MapCount[0];

	float MaxPoints = 0.0;

	if (GetConVarBool(g_hDBMapcycle))
	{
		// There is no "maxpoints" since WR points are always scaling, I'll just use total map completion points + bonus wr points (bonus wrs dont scale)
		// Map Points (arrays start at 1 lol!)
		MaxPoints += g_pr_MapCount[1] * 25.0;
		MaxPoints += g_pr_MapCount[2] * 50.0;
		MaxPoints += g_pr_MapCount[3] * 100.0;
		MaxPoints += g_pr_MapCount[4] * 200.0;
		MaxPoints += g_pr_MapCount[5] * 400.0;
		MaxPoints += g_pr_MapCount[6] * 600.0;

		// Bonus Points
		MaxPoints += (float(g_totalBonusCount) * 200.0);
	}
	else
	{
		// Old way of calculating max points (inaccurate since map WR points aren't flat 700)
		MaxPoints = (float(mapcount) * 700.0) + (float(g_totalBonusCount) * 200.0);
	}

	// Load rank cfg
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), SKILLGROUP_PATH);
	if (FileExists(sPath))
	{
		Handle hKeyValues = CreateKeyValues("SkillGroups");
		if (FileToKeyValues(hKeyValues, sPath) && KvGotoFirstSubKey(hKeyValues))
		{
			SkillGroup RankValue;

			if (g_hSkillGroups == null)
				g_hSkillGroups = CreateArray(sizeof(SkillGroup));
			else
				ClearArray(g_hSkillGroups);

			char sRankName[128], sRankNameColored[128], sNameColour[32], sBuffer[32];
			float fPercentage;
			int points, pointsBot, pointsTop, rankBot, rankTop, rank, i = 0;
			do
			{
				i++;
				// Get Rankname & namecolour
				KvGetString(hKeyValues, "rankTitle", sRankName, 128);
				KvGetString(hKeyValues, "rankTitle", sRankNameColored, 128);
				KvGetString(hKeyValues, "nameColour", sNameColour, 32, "{default}");

				// Get points requirement
				points = -1;
				pointsBot = -1;
				pointsTop = -1;

				KvGetString(hKeyValues, "points", sBuffer, 32, "invalid");

				// Is the points requirement a range?
				if (StrContains(sBuffer, "-") != -1)
				{
					char sBuffer2[2][32];
					ExplodeString(sBuffer, "-", sBuffer2, 2, 32);
					pointsBot = StringToInt(sBuffer2[0]);
					pointsTop = StringToInt(sBuffer2[1]);
				}
				else if (!StrEqual(sBuffer, "invalid"))
					points = StringToInt(sBuffer);

				// Get percentage
				fPercentage = KvGetFloat(hKeyValues, "percentage", 0.0);

				// Calculate percentage requirement
				if (fPercentage > 0.0)
					points = RoundToCeil(MaxPoints * fPercentage);

				// Get rank requirement
				rank = -1;
				rankBot = -1;
				rankTop = -1;

				KvGetString(hKeyValues, "rank", sBuffer, 32, "invalid");

				// Is the rank requirement a range?
				if (StrContains(sBuffer, "-") != -1)
				{
					char sBuffer2[2][32];
					ExplodeString(sBuffer, "-", sBuffer2, 2, 32);
					rankBot = StringToInt(sBuffer2[0]);
					rankTop = StringToInt(sBuffer2[1]);
				}
				else if (!StrEqual(sBuffer, "invalid"))
					rank = StringToInt(sBuffer);

				// Ignore invalid entries
				if (pointsBot == -1 && pointsTop == -1 && points == -1 && fPercentage == 0.0 && rankBot == -1 && rankTop == -1 && rank == -1)
				{
					LogError("Skillgroup %i is invalid", i);
					continue;
				}

				RankValue.PointReq = points;
				RankValue.PointsBot = pointsBot;
				RankValue.PointsTop = pointsTop;
				RankValue.RankBot = rankBot;
				RankValue.RankTop = rankTop;
				RankValue.RankReq = rank;

				// Remove colors from rank name
				CRemoveTags(sRankName, 128);

				Format(RankValue.RankName, sizeof(SkillGroup::RankName), "%s", sRankName);
				Format(RankValue.RankNameColored, sizeof(SkillGroup::RankNameColored), "%s", sRankNameColored);
				Format(RankValue.NameColour, sizeof(SkillGroup::NameColour), "%s", sNameColour);

				PushArrayArray(g_hSkillGroups, RankValue, sizeof(RankValue));
			} while (KvGotoNextKey(hKeyValues));
		}

		delete hKeyValues;
	}
	else
		SetFailState("[surftimer] %s not found.", SKILLGROUP_PATH);

}

public void SetPlayerRank(int client)
{
	if (IsFakeClient(client))
		return;

	if (g_hSkillGroups == null)
	{
		CreateTimer(5.0, reloadRank, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		return;
	}

	int style = g_iCurrentStyle[client];
	int rank = g_PlayerRank[client][style];
	int points = g_pr_points[client][style];

	SkillGroup RankValue;
	int index = GetSkillgroupIndex(rank, points);
	GetArrayArray(g_hSkillGroups, index, RankValue, sizeof(SkillGroup));

	if (g_bEnforceTitle[client])
	{
		// g_iEnforceTitleType[client], 0 = chat, 1 = scoreboard, 2 = both
		ReplaceString(g_szEnforcedTitle[client], sizeof(g_szEnforcedTitle), "{style}", g_szStyleAcronyms[style]);
		if (g_iEnforceTitleType[client] == 0 || g_iEnforceTitleType[client] == 2)
		{
			Format(g_pr_rankname_style[client], sizeof(SkillGroup::RankName), RankValue.RankName);
			Format(g_pr_rankname[client], sizeof(SkillGroup::RankName), RankValue.RankName);
			ReplaceString(g_pr_rankname[client], 128, "{style}", "");
			Format(g_szRankName[client], sizeof(SkillGroup::RankName), RankValue.RankName);
			Format(g_pr_namecolour[client], sizeof(SkillGroup::NameColour), RankValue.NameColour);
			Format(g_pr_chat_coloredrank[client], 256, g_szEnforcedTitle[client]);
		}

		if (g_iEnforceTitleType[client] == 1 || g_iEnforceTitleType[client] == 2)
		{
			char szTitle[256];
			Format(szTitle, 256, g_szEnforcedTitle[client]);
			CRemoveTags(szTitle, 256);
			Format(g_pr_rankname[client], 256, szTitle);
		}
	}
	else if (!g_bDbCustomTitleInUse[client])
	{
		// Player is not using a title
		if (GetConVarBool(g_hPointSystem))
		{
			char szName[MAX_NAME_LENGTH];
			GetClientName(client, szName, sizeof(szName));
			CRemoveColors(szName, sizeof(szName));

			Format(g_pr_chat_coloredrank[client], sizeof(SkillGroup::RankNameColored), RankValue.RankNameColored);
			Format(g_pr_chat_coloredrank_style[client], sizeof(SkillGroup::RankNameColored), RankValue.RankNameColored);
			ReplaceString(g_pr_chat_coloredrank[client], 128, "{style}", "");
			Format(g_pr_rankname_style[client], sizeof(SkillGroup::RankName), RankValue.RankName);
			Format(g_pr_rankname[client], sizeof(SkillGroup::RankName), RankValue.RankName);
			ReplaceString(g_pr_rankname[client], 128, "{style}", "");
			Format(g_szRankName[client], sizeof(SkillGroup::RankName), RankValue.RankName);
			Format(g_pr_namecolour[client], sizeof(SkillGroup::NameColour), RankValue.NameColour);
		}
	}
	else
	{
		// Player is using a title
		if (GetConVarBool(g_hPointSystem))
		{
		}
	}
}

public int GetSkillgroupIndex(int rank, int points)
{
	int size = GetArraySize(g_hSkillGroups);
	for (int i = 0; i < size; i++)
	{
		SkillGroup RankValue;
		GetArrayArray(g_hSkillGroups, i, RankValue, sizeof(SkillGroup));
		if (RankValue.RankReq > -1)
		{
			if (rank == RankValue.RankReq)
				return i;
		}
		else if (RankValue.RankBot > -1 && RankValue.RankTop > -1)
		{
			if (rank >= RankValue.RankBot && rank <= RankValue.RankTop)
				return i;
		}
		else if (RankValue.PointsBot > -1 && RankValue.PointsTop > -1)
		{
			if (points >= RankValue.PointsBot && points <= RankValue.PointsTop)
				return i;
		}
		else if (RankValue.PointReq > -1)
		{
			if (i == (size - 1)) // Last Rank
			{
				if (points >= RankValue.PointReq)
					return i;
			}
			else if (i == 0) // First Rank
			{
				if (points <= RankValue.PointReq)
					return i;
			}
			else // Mid ranks
			{
				SkillGroup RankValueNext;
				GetArrayArray(g_hSkillGroups, (i+1), RankValueNext, sizeof(SkillGroup));
				if (RankValueNext.PointReq > -1)
				{
					if (points >= RankValue.PointReq && points < RankValueNext.PointReq)
						return i;
				}
				else if (RankValueNext.RankReq > -1)
				{
					if (points >= RankValue.PointReq && rank >= RankValueNext.RankReq)
						return i;
				}
				else if (RankValueNext.RankTop > -1)
				{
					if (points >= RankValue.PointReq)
						return i;
				}
			}
		}
	}
	return 0;
}

stock Action PrintSpecMessageAll(int client)
{
	char szName[64];
	GetClientName(client, szName, sizeof(szName));
	parseColorsFromString(szName, 64);

	char szTextToAll[1024];
	GetCmdArgString(szTextToAll, sizeof(szTextToAll));
	StripQuotes(szTextToAll);
	if (StrEqual(szTextToAll, "") || StrEqual(szTextToAll, " ") || StrEqual(szTextToAll, "  "))
		return Plugin_Handled;

	parseColorsFromString(szTextToAll, 1024);
	char szChatRank[64];
	Format(szChatRank, 64, "%s", g_pr_chat_coloredrank[client]);

	if (GetConVarBool(g_hPointSystem) && GetConVarBool(g_hColoredNames) && g_bDbCustomTitleInUse[client])
		setNameColor(szName, g_iCustomColours[client][0], 64);
	// fluffys

	if (g_bHasCustomTextColour[client])
		setTextColor(szTextToAll, g_iCustomColours[client][1], 1024);

	char szChatRankColor[1024];
	Format(szChatRankColor, 1024, "%s", g_pr_chat_coloredrank[client]);
	CGetRankColor(szChatRankColor, 1024);
	if (GetConVarBool(g_hPointSystem) && GetConVarBool(g_hColoredNames) && !g_bDbCustomTitleInUse[client])
		Format(szName, sizeof(szName), "{%s}%s", szChatRankColor, szName);

	if (GetConVarBool(g_hCountry))
		CPrintToChatAll("%t", "Misc20", g_szCountryCode[client], szChatRank, szName, szTextToAll);
	else if (GetConVarBool(g_hPointSystem))
	{
		if (StrContains(szChatRank, "{blue}") != -1)
		{
			char szPlayerTitle2[256][2];
			ExplodeString(szChatRank, "{blue}", szPlayerTitle2, 2, 256);
			char szPlayerTitleColor[1024];
			Format(szPlayerTitleColor, 1024, "%s", szPlayerTitle2[1]);
			if (GetConVarBool(g_hPointSystem) && GetConVarBool(g_hColoredNames) && !g_bDbCustomTitleInUse[client])
				Format(szName, sizeof(szName), "{%s}%s", szPlayerTitleColor, szName);
			if (IsPlayerAlive(client))
				CPrintToChatAll("%t", "Misc21", szPlayerTitle2[0], szPlayerTitle2[1], szName, szTextToAll);
			else
				CPrintToChatAll("%t", "Misc22", szPlayerTitle2[0], szPlayerTitle2[1], szName, szTextToAll);

			return Plugin_Handled;
		}
		else if (StrContains(szChatRank, "{orange}") != -1)
		{
			char szPlayerTitle2[256][2];
			ExplodeString(szChatRank, "{orange}", szPlayerTitle2, 2, 256);
			char szPlayerTitleColor[1024];
			Format(szPlayerTitleColor, 1024, "%s", szPlayerTitle2[1]);
			if (GetConVarBool(g_hPointSystem) && GetConVarBool(g_hColoredNames) && !g_bDbCustomTitleInUse[client])
				Format(szName, sizeof(szName), "{%s}%s", szPlayerTitleColor, szName);
			if (IsPlayerAlive(client))
				CPrintToChatAll("%t", "Misc23", szPlayerTitle2[0], szPlayerTitle2[1], szName, szTextToAll);
			else
				CPrintToChatAll("%t", "Misc24", szPlayerTitle2[0], szPlayerTitle2[1], szName, szTextToAll);

			return Plugin_Handled;
		}
		else
			CPrintToChatAll("%t", "Misc25", szChatRank, szName, szTextToAll);
		}
		else
			CPrintToChatAll("%t", "Misc26", szName, szTextToAll);

	for (int i = 1; i <= MaxClients; i++)
		if (IsValidClient(i))
		{
			if (GetConVarBool(g_hPointSystem))
				PrintToConsole(i, "%t", "Misc27", g_pr_rankname[client], szName, szTextToAll);
			else
				PrintToConsole(i, "%t", "Misc28", szName, szTextToAll);
		}
	return Plugin_Handled;
}
// http:// pastebin.com/YdUWS93H
public bool CheatFlag(const char[] voice_inputfromfile, bool isCommand, bool remove)
{
	if (remove)
	{
		if (!isCommand)
		{
			Handle hConVar = FindConVar(voice_inputfromfile);
			if (hConVar != null)
			{
				int flags = GetConVarFlags(hConVar);
				SetConVarFlags(hConVar, flags &= ~FCVAR_CHEAT);
				return true;
			}
			else
				return false;
		}
		else
		{
			int flags = GetCommandFlags(voice_inputfromfile);
			if (SetCommandFlags(voice_inputfromfile, flags &= ~FCVAR_CHEAT))
				return true;
			else
				return false;
		}
	}
	else
	{
		if (!isCommand)
		{
			Handle hConVar = FindConVar(voice_inputfromfile);
			if (hConVar != null)
			{
				int flags = GetConVarFlags(hConVar);
				SetConVarFlags(hConVar, flags & FCVAR_CHEAT);
				return true;
			}
			else
				return false;

		} else
		{
			int flags = GetCommandFlags(voice_inputfromfile);
			if (SetCommandFlags(voice_inputfromfile, flags & FCVAR_CHEAT))
				return true;
			else
				return false;

		}
	}
}

public void StringRGBtoInt(char color[24], intColor[4])
{
	char sPart[4][24];
	ExplodeString(color, " ", sPart, sizeof(sPart), sizeof(sPart[]));
	intColor[0] = StringToInt(sPart[0]);
	intColor[1] = StringToInt(sPart[1]);
	intColor[2] = StringToInt(sPart[2]);
	intColor[3] = 255;
}

public void GetRGBColor(int bot, char color[256])
{
	char sPart[4][24];
	ExplodeString(color, " ", sPart, sizeof(sPart), sizeof(sPart[]));

	if (bot == 0)
	{
		g_ReplayBotColor[0] = StringToInt(sPart[0]);
		g_ReplayBotColor[1] = StringToInt(sPart[1]);
		g_ReplayBotColor[2] = StringToInt(sPart[2]);
	}
	else
		if (bot == 1)
	{
		g_BonusBotColor[0] = StringToInt(sPart[0]);
		g_BonusBotColor[1] = StringToInt(sPart[1]);
		g_BonusBotColor[2] = StringToInt(sPart[2]);
	}

	if (bot == 0 && g_RecordBot != -1 && IsValidClient(g_RecordBot))
		SetEntityRenderColor(g_RecordBot, g_ReplayBotColor[0], g_ReplayBotColor[1], g_ReplayBotColor[2], 50);
	else if (bot == 0 && g_WrcpBot != -1 && IsValidClient(g_WrcpBot))
		SetEntityRenderColor(g_WrcpBot, 255, 0, 255, 50);
	else
		if (bot == 1 && g_BonusBot != -1 && IsValidClient(g_BonusBot))
		SetEntityRenderColor(g_BonusBot, g_BonusBotColor[0], g_BonusBotColor[1], g_BonusBotColor[2], 50);
}

public void SpecList(int client)
{
	if (!IsValidClient(client) || IsFakeClient(client) || GetClientMenu(client) != MenuSource_None)
		return;

	if (!StrEqual(g_szPlayerPanelText[client], ""))
	{
		Handle panel = CreatePanel();
		DrawPanelText(panel, g_szPlayerPanelText[client]);
		SendPanelToClient(panel, client, PanelHandler, 1);
		delete panel;
	}
}

public int PanelHandler(Handle menu, MenuAction action, int param1, int param2)
{
}

public bool TraceRayDontHitSelf(int entity, int mask, any data)
{
	return entity != data && !(0 < entity <= MaxClients);
}

stock int BooltoInt(bool status)
{
	return (status) ? 1:0;
}

public void AttackProtection(int client, int &buttons)
{
	if (GetConVarBool(g_hAttackSpamProtection))
	{
		char classnamex[64];
		GetClientWeapon(client, classnamex, 64);
		if (StrContains(classnamex, "knife", true) == -1 && g_AttackCounter[client] >= 40)
		{
			if (buttons & IN_ATTACK)
			{
				int ent;
				ent = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
				if (IsValidEntity(ent))
					SetEntPropFloat(ent, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() + 2.0);
			}
		}
	}
}

public void CheckRun(int client)
{
	if (!IsValidClient(client) || IsFakeClient(client))
		return;

	if (g_bTimerRunning[client])
	{
		if (g_fCurrentRunTime[client] > g_fPersonalStyleRecord[g_iCurrentStyle[client]][client] && !g_bMissedMapBest[client] && !g_bPause[client] && g_iClientInZone[client][2] == 0)
		{
			g_bMissedMapBest[client] = true;
			if (g_fPersonalStyleRecord[g_iCurrentStyle[client]][client] > 0.0) {
				CPrintToChat(client, "%t", "MissedMapBest", g_szChatPrefix, g_szPersonalStyleRecord[g_iCurrentStyle[client]][client]);
				if (g_iAutoReset[client] && g_iCurrentStyle[client] == 0) {
					Command_Restart(client, 1);
					CPrintToChat(client, "%t", "AutoResetMessage1", g_szChatPrefix);
					CPrintToChat(client, "%t", "AutoResetMessage2", g_szChatPrefix);
				} else if (g_iAutoReset[client] && g_iCurrentStyle[client] != 0) {
					CPrintToChat(client, "%t", "AutoResetMessageStyle", g_szChatPrefix, g_szStyleMenuPrint[g_iCurrentStyle[client]]);
					CPrintToChat(client, "%t", "AutoResetMessage2", g_szChatPrefix);
				}
			}
			EmitSoundToClient(client, "buttons/button18.wav", client);
		}
		else
		{
			if (g_fCurrentRunTime[client] > g_fStylePersonalRecordBonus[g_iCurrentStyle[client]][g_iClientInZone[client][2]][client] && g_iClientInZone[client][2] > 0 && !g_bPause[client] && !g_bMissedBonusBest[client])
			{
				if (g_fStylePersonalRecordBonus[g_iCurrentStyle[client]][g_iClientInZone[client][2]][client] > 0.0)
				{
					g_bMissedBonusBest[client] = true;
					CPrintToChat(client, "%t", "Misc29", g_szChatPrefix, g_szStylePersonalRecordBonus[g_iCurrentStyle[client]][g_iClientInZone[client][2]][client]);
					if (g_iAutoReset[client] && g_iCurrentStyle[client] == 0) {
						Command_Teleport(client, 0);
						CPrintToChat(client, "%t", "AutoResetMessage1", g_szChatPrefix);
						CPrintToChat(client, "%t", "AutoResetMessage2", g_szChatPrefix);
					} else if (g_iAutoReset[client] && g_iCurrentStyle[client] != 0) {
						CPrintToChat(client, "%t", "AutoResetMessageStyle", g_szChatPrefix, g_szStyleMenuPrint[g_iCurrentStyle[client]]);
						CPrintToChat(client, "%t", "AutoResetMessage2", g_szChatPrefix);
					}
					EmitSoundToClient(client, "buttons/button18.wav", client);
				}
			}
		}
	}
}

public void NoClipCheck(int client)
{
	MoveType mt;
	mt = GetEntityMoveType(client);
	if (!(g_bOnGround[client]))
	{
		if (mt == MOVETYPE_NOCLIP)
			g_bNoClipUsed[client] = true;
	}
	if (mt == MOVETYPE_NOCLIP && (g_bTimerRunning[client]))
	{
		Client_Stop(client, 1);
	}
}

public void AutoBhopFunction(int client, int &buttons)
{
	if (!IsValidClient(client))
		return;
	if (g_bAutoBhop && g_bAutoBhopClient[client])
	{
		if (buttons & IN_JUMP)
			if (!(g_bOnGround[client]))
			if (!(GetEntityMoveType(client) & MOVETYPE_LADDER))
			if (GetEntProp(client, Prop_Data, "m_nWaterLevel") <= 1)
			buttons &= ~IN_JUMP;

	}
}

public void SpecListMenuDead(int client) // What Spectators see
{
	char szTick[32];
	Format(szTick, 32, "%i", g_Server_Tickrate);
	int ObservedUser;
	ObservedUser = -1;
	char sSpecs[512];
	Format(sSpecs, 512, "");
	int SpecMode;
	ObservedUser = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
	SpecMode = GetEntProp(client, Prop_Send, "m_iObserverMode");

	if (SpecMode == 4 || SpecMode == 5)
	{
		g_SpecTarget[client] = ObservedUser;
		int count;
		count = 0;
		// Speclist
		if (1 <= ObservedUser <= MaxClients)
		{
			int x;
			char szTime2[32];
			char szProBest[32];
			char szPlayerRank[64];
			Format(szPlayerRank, 32, "");
			char szStage[32];

			for (x = 1; x <= MaxClients; x++)
			{
				if (IsValidClient(x) && !IsFakeClient(client) && !IsPlayerAlive(x) && GetClientTeam(x) >= 1 && GetClientTeam(x) <= 3 && !g_iSilentSpectate[x])
				{

					SpecMode = GetEntProp(x, Prop_Send, "m_iObserverMode");
					if (SpecMode == 4 || SpecMode == 5)
					{
						int ObservedUser2;
						ObservedUser2 = GetEntPropEnt(x, Prop_Send, "m_hObserverTarget");

						if (ObservedUser == ObservedUser2)
						{
							count++;
							if (count < 6)
								Format(sSpecs, 512, "%s%N\n", sSpecs, x);
						}
						if (count == 6)
							Format(sSpecs, 512, "%s...", sSpecs);
					}
				}
			}

			// Rank
			if (GetConVarBool(g_hPointSystem))
			{
				if (g_pr_points[ObservedUser][0] != 0)
				{
					char szRank[32];
					if (g_PlayerRank[ObservedUser][0] > g_pr_RankedPlayers[0])
						Format(szRank, 32, "-");
					else
						Format(szRank, 32, "%i", g_PlayerRank[ObservedUser][0]);
					Format(szPlayerRank, 32, "Rank: #%s/%i", szRank, g_pr_RankedPlayers[0]);
				}
				else
					Format(szPlayerRank, 32, "Rank: NA / %i", g_pr_RankedPlayers[0]);
			}

			if (g_fPersonalStyleRecord[0][ObservedUser] > 0.0)
			{
				FormatTimeFloat(client, g_fPersonalStyleRecord[0][ObservedUser], 3, szTime2, sizeof(szTime2));
				Format(szProBest, 32, "%s (#%i/%i)", szTime2, g_StyleMapRank[0][ObservedUser], g_StyleMapTimesCount[0]);
			}
			else
				Format(szProBest, 32, "None");

			if (g_bhasStages) // There are stages
				Format(szStage, 32, "Stage: %i / %i", g_Stage[g_iClientInZone[ObservedUser][2]][ObservedUser], (g_mapZonesTypeCount[g_iClientInZone[ObservedUser][2]][3] + 1));
			else
				Format(szStage, 32, "Linear");

			if (g_Stage[g_iClientInZone[client][2]][ObservedUser] == 999) // if player is in stage 999
				Format(szStage, 32, "Bonus");

			if (!StrEqual(sSpecs, ""))
			{
				char szName[MAX_NAME_LENGTH];
				GetClientName(ObservedUser, szName, MAX_NAME_LENGTH);
				if (g_bTimerRunning[ObservedUser])
				{
					char szTime[32];
					float Time;
					Time = GetGameTime() - g_fStartTime[ObservedUser] - g_fPauseTime[ObservedUser];
					FormatTimeFloat(client, Time, 4, szTime, sizeof(szTime));
					if (!g_bPause[ObservedUser])
					{
						if (!IsFakeClient(ObservedUser))
						{
							Format(g_szPlayerPanelText[client], 512, "Specs (%i):\n%s\n  \n%s\n%s\nRecord: %s\n\n%s\n", count, sSpecs, szTime, szPlayerRank, szProBest, szStage);
							if (!g_bShowSpecs[client])
								Format(g_szPlayerPanelText[client], 512, "Specs (%i)\n \n%s\n%s\nRecord: %s\n\nStage: %s\n", count, szTime, szPlayerRank, szProBest, szStage);
						}
						else
						{
							if (ObservedUser == g_RecordBot)
								Format(g_szPlayerPanelText[client], 512, "[Map Record Replay]\n%s\nTickrate: %s\nSpecs: %i\n\n%s\n", szTime, szTick, count, szStage);
							else
								if (ObservedUser == g_BonusBot)
									Format(g_szPlayerPanelText[client], 512, "[%s Record Replay]\n%s\nTickrate: %s\nSpecs: %i\n\n%s\n", g_szZoneGroupName[g_iClientInZone[g_BonusBot][2]], szTime, szTick, count, szStage);

						}
					}
					else
					{
						if (ObservedUser == g_RecordBot)
							Format(g_szPlayerPanelText[client], 512, "[Map Record Replay]\nPAUSED\nTickrate: %s\nSpecs: %i\n\n%s\n", szTick, count, szStage);
						else
							if (ObservedUser == g_BonusBot)
								Format(g_szPlayerPanelText[client], 512, "[%s Record Replay]\nPAUSED\nTickrate: %s\nSpecs: %i\n\nBonus\n", g_szZoneGroupName[g_iClientInZone[g_BonusBot][2]], szTick, count);
					}
				}
				else
				{
					if (ObservedUser != g_RecordBot)
					{
						Format(g_szPlayerPanelText[client], 512, "%Specs (%i):\n%s\n \n%s\nRecord: %s\n", count, sSpecs, szPlayerRank, szProBest);
						if (!g_bShowSpecs[client])
							Format(g_szPlayerPanelText[client], 512, "Specs (%i)\n \n%s\nRecord: %s\n", count, szPlayerRank, szProBest);
					}
				}

				if (g_bShowSpecs[client])
				{
					if (ObservedUser != g_RecordBot && ObservedUser != g_BonusBot && ObservedUser != g_WrcpBot)
						Format(g_szPlayerPanelText[client], 512, "Specs (%i):\n%s\n \n%s\nRecord: %s\n\n%s\n", count, sSpecs, szPlayerRank, szProBest, szStage);
					else
					{
						if (ObservedUser == g_RecordBot)
							Format(g_szPlayerPanelText[client], 512, "Map Replay\n%s (%s)\n \nSpecs (%i):\n%s\n \n%s\n", g_szReplayName, g_szReplayTime, count, sSpecs, szStage);
						else if (ObservedUser == g_BonusBot)
							Format(g_szPlayerPanelText[client], 512, "Bonus Replay\n%s (%s)\n \nSpecs (%i):\n%s\n \nBonus\n", g_szBonusName, g_szBonusTime, count, sSpecs);
						else if (ObservedUser == g_WrcpBot)
						{
							if (g_bManualStageReplayPlayback)
							{
								int stage = g_iSelectedReplayStage;
								Format(g_szPlayerPanelText[client], 512, "Stage: %i Replay (%i)\n%s (%s)\n \nSpecs (%i):\n%s\n", stage, g_iManualStageReplayCount + 1, g_szWrcpReplayName[stage],  g_szWrcpReplayTime[stage], count, sSpecs);
							}
							else
							{
								int stage = g_StageReplayCurrentStage;
								Format(g_szPlayerPanelText[client], 512, "Stage: %i Replay (%i)\n%s (%s)\n \nSpecs (%i):\n%s\n", g_StageReplayCurrentStage, g_StageReplaysLoop, g_szWrcpReplayName[stage],  g_szWrcpReplayTime[stage], count, sSpecs);
							}
						}

					}
				}
				if (!g_bShowSpecs[client])
				{
					if (ObservedUser != g_RecordBot)
						Format(g_szPlayerPanelText[client], 512, "%s\nRecord: %s\n\n%s\n", szPlayerRank, szProBest, szStage);
					else
					{
						if (ObservedUser == g_RecordBot)
							Format(g_szPlayerPanelText[client], 512, "Record replay of\n%s\n \nTickrate: %s\n\n%s\n", g_szReplayName, szTick, szStage);
						else
							if (ObservedUser == g_BonusBot)
							Format(g_szPlayerPanelText[client], 512, "Bonus replay of\n%s\n \nTickrate: %s\n\nBonus\n", g_szBonusName, szTick, szStage);

					}
				}
				SpecList(client);
			}
		}
	}
	else
		g_SpecTarget[client] = -1;
}

public void SpecListMenuAlive(int client) // What player sees
{

	if (IsFakeClient(client) || !g_bShowSpecs[client] || GetClientMenu(client) != MenuSource_None)
		return;

	// Spec list for players
	Format(g_szPlayerPanelText[client], 512, "");
	char sSpecs[512];
	int SpecMode;
	Format(sSpecs, 512, "");
	int count;
	count = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && !IsFakeClient(client) && !IsPlayerAlive(i) && !g_bFirstTeamJoin[i] && g_bSpectate[i] && !g_iSilentSpectate[i])
		{
			SpecMode = GetEntProp(i, Prop_Send, "m_iObserverMode");
			if (SpecMode == 4 || SpecMode == 5)
			{
				int Target;
				Target = GetEntPropEnt(i, Prop_Send, "m_hObserverTarget");
				if (Target == client)
				{
					count++;
					if (count < 6)
						Format(sSpecs, 512, "%s%N\n", sSpecs, i);

				}
				if (count == 6)
					Format(sSpecs, 512, "%s...", sSpecs);
			}
		}
	}
	if (count > 0)
	{
		if (g_bShowSpecs[client])
			Format(g_szPlayerPanelText[client], 512, "Specs (%i):\n%s ", count, sSpecs);

		SpecList(client);
	}
	else
		Format(g_szPlayerPanelText[client], 512, "");
}

public void LoadInfoBot()
{
	if (!GetConVarBool(g_hInfoBot))
		return;

	g_InfoBot = -1;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i) || !IsFakeClient(i) || IsClientSourceTV(i) || i == g_RecordBot || i == g_BonusBot || i == g_WrcpBot)
			continue;
		g_InfoBot = i;
		break;
	}
	if (IsValidClient(g_InfoBot))
	{
		Format(g_pr_rankname[g_InfoBot], 128, "BOT");
		CS_SetClientClanTag(g_InfoBot, "");
		SetEntProp(g_InfoBot, Prop_Send, "m_iAddonBits", 0);
		SetEntProp(g_InfoBot, Prop_Send, "m_iPrimaryAddon", 0);
		SetEntProp(g_InfoBot, Prop_Send, "m_iSecondaryAddon", 0);
		SetEntProp(g_InfoBot, Prop_Send, "m_iObserverMode", 1);
		SetInfoBotName(g_InfoBot);
	}
	else
	{
		setBotQuota();
		CreateTimer(0.5, RefreshInfoBot, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void CreateNavFile()
{
	// Check if source nav file exists
	char szSource[PLATFORM_MAX_PATH];
	Format(szSource, sizeof(szSource), "maps/replay_bot.nav");
	if (!FileExists(szSource))
	{
		LogError("[SurfTimer] Failed to create .nav files. %s doesn't exist!", szSource);
		return;
	}

	// Generate new nav file
	char szNav[PLATFORM_MAX_PATH];
	Format(szNav, sizeof(szNav), "maps/%s.nav", g_szMapName);
	if (!FileExists(szNav))
	{
		File_Copy(szSource, szNav);
		ForceChangeLevel(g_szMapName, ".nav file generated");
	}
}

public Action RefreshInfoBot(Handle timer)
{
	LoadInfoBot();
}

public void SetInfoBotName(int ent)
{
	char szBuffer[64];
	char sNextMap[128];
	if (!IsValidClient(g_InfoBot) || !GetConVarBool(g_hInfoBot))
		return;
	if (g_bMapChooser && EndOfMapVoteEnabled() && !HasEndOfMapVoteFinished())
		Format(sNextMap, sizeof(sNextMap), "Pending Vote");
	else
	{
		GetNextMap(sNextMap, sizeof(sNextMap));
		char mapPieces[6][128];
		int lastPiece = ExplodeString(sNextMap, "/", mapPieces, sizeof(mapPieces), sizeof(mapPieces[]));
		Format(sNextMap, sizeof(sNextMap), "%s", mapPieces[lastPiece - 1]);
	}
	int iInfoBotTimeleft;
	GetMapTimeLeft(iInfoBotTimeleft);
	float ftime = float(iInfoBotTimeleft);
	char szTime[32];
	FormatTimeFloat(g_InfoBot, ftime, 4, szTime, sizeof(szTime));
	Handle hTmp = FindConVar("mp_timelimit");
	int iTimeLimit = GetConVarInt(hTmp);
	delete hTmp;
	if (GetConVarBool(g_hMapEnd) && iTimeLimit > 0)
		Format(szBuffer, sizeof(szBuffer), "%s (in %s)", sNextMap, szTime);
	else
		Format(szBuffer, sizeof(szBuffer), "Pending Vote (no time limit)");
	SetClientName(g_InfoBot, szBuffer);
	Client_SetScore(g_InfoBot, 9999);
	CS_SetClientClanTag(g_InfoBot, "NEXTMAP");
}

public void CenterHudDead(int client)
{
	char szTick[32];
	char obsAika[128];
	float obsTimer;
	Format(szTick, 32, "%i", g_Server_Tickrate);
	int ObservedUser;
	ObservedUser = -1;
	int SpecMode;
	ObservedUser = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
	SpecMode = GetEntProp(client, Prop_Send, "m_iObserverMode");
	if (SpecMode == 4 || SpecMode == 5)
	{
		g_SpecTarget[client] = ObservedUser;
		// Show Keys
		char sResult[256];
		int Buttons;
		if (IsValidClient(ObservedUser))
		{
			Buttons = g_LastButton[ObservedUser];
			if (Buttons & IN_MOVELEFT)
				Format(sResult, sizeof(sResult), "<font color='#b8b'>A</font>");
			else
				Format(sResult, sizeof(sResult), "_");
			if (Buttons & IN_FORWARD)
				Format(sResult, sizeof(sResult), "%s <font color='#b8b'>W</font>", sResult);
			else
				Format(sResult, sizeof(sResult), "%s _", sResult);
			if (Buttons & IN_BACK)
				Format(sResult, sizeof(sResult), "%s <font color='#b8b'>S</font>", sResult);
			else
				Format(sResult, sizeof(sResult), "%s _", sResult);
			if (Buttons & IN_MOVERIGHT)
				Format(sResult, sizeof(sResult), "%s <font color='#b8b'>D</font>", sResult);
			else
				Format(sResult, sizeof(sResult), "%s _", sResult);
			if (Buttons & IN_DUCK)
				Format(sResult, sizeof(sResult), "%s - <font color='#b8b'>C</font>", sResult);
			else
				Format(sResult, sizeof(sResult), "%s - _", sResult);
			if (Buttons & IN_JUMP)
				Format(sResult, sizeof(sResult), "%s <font color='#b8b'>J</font>", sResult);
			else
				Format(sResult, sizeof(sResult), "%s _", sResult);
			if (Buttons & IN_LEFT)
				Format(sResult, sizeof(sResult), "%s <font color='#b8b'>L</font>", sResult);
			else
				Format(sResult, sizeof(sResult), "%s _", sResult);
			if (Buttons & IN_RIGHT)
				Format(sResult, sizeof(sResult), "%s <font color='#b8b'>R</font>", sResult);
			else
				Format(sResult, sizeof(sResult), "%s _", sResult);

			if (IsFakeClient(ObservedUser))
			{
				if (ObservedUser == g_RecordBot)
					Format(obsAika, sizeof(obsAika), "<font color='#ec8'>%s</font>", g_szReplayTime);
				else if (ObservedUser == g_BonusBot)
					Format(obsAika, sizeof(obsAika), "<font color='#ec8'>%s</font>", g_szBonusTime);
				else if (ObservedUser == g_WrcpBot)
					Format(obsAika, sizeof(obsAika), "<font color='#ec8'>%s</font>", g_szWrcpReplayTime[g_iCurrentlyPlayingStage]);

				PrintCSGOHUDText(client, "<pre>%s\nSpeed: <font color='#5e5'>%i u/s\n%s</pre>", obsAika, RoundToNearest(g_fLastSpeed[ObservedUser]), sResult);
				return;
			}
			else if (g_bTimerRunning[ObservedUser])
			{
				obsTimer = GetGameTime() - g_fStartTime[ObservedUser] - g_fPauseTime[ObservedUser];
				FormatTimeFloat(client, obsTimer, 3, obsAika, sizeof(obsAika));
			}
			else if (g_bWrcpTimeractivated[ObservedUser] && !g_bTimerRunning[ObservedUser])
			{
				obsTimer = GetGameTime() - g_fStartWrcpTime[ObservedUser] - g_fPauseTime[ObservedUser];
				FormatTimeFloat(client, obsTimer, 3, obsAika, sizeof(obsAika));
			}
			else if (!g_bTimerEnabled[ObservedUser])
				obsAika = "<font color='#f32'>Disabled</font>";
			else {
				obsAika = "<font color='#f32'>00:00:00</font>";
			}
			char timerText[32] = "";
			if (g_iClientInZone[ObservedUser][2] > 0)
				Format(timerText, 32, "[%s] ", g_szZoneGroupName[g_iClientInZone[ObservedUser][2]]);
			if (g_bPracticeMode[ObservedUser])
				Format(timerText, 32, "[P] ");
			else if (g_iCurrentStyle[ObservedUser] != 0)
				Format(timerText, 32, "%s ", g_szStyleHud[ObservedUser]);

			PrintCSGOHUDText(client, "<pre>%s<font color='#5e5'>%s</font>\nSpeed: <font color='#5e5'>%i u/s\n%s</pre>", timerText, obsAika, RoundToNearest(g_fLastSpeed[ObservedUser]), sResult);
		}
	}
	else
		g_SpecTarget[client] = -1;
}

public void CenterHudAlive(int client)
{
	if (!IsValidClient(client))
		return;

	if (g_bCentreHud[client])
	{
		int style = g_iCurrentStyle[client];
		char module[6][1024];
		char pAika[54];

		float gametime = GetGameTime();

		for (int i = 0; i < 6; i++)
		{
			if (g_iCentreHudModule[client][i] == 0)
			{
				Format(module[i], 128, "                         ");
			}
			if (g_iCentreHudModule[client][i] == 1)
			{
				// Timer
				if (g_bTimerRunning[client])
				{
					FormatTimeFloat(client, g_fCurrentRunTime[client], 3, pAika, 128);
					if (g_bPause[client])
					{
						// Paused
						Format(module[i], 128, "<font color='#ec8'>%s       </font>", pAika);
					}
					else if (g_bPracticeMode[client])
					{
						// Prac mode
						Format(module[i], 128, "<font color='#eee'>[P]: %s       </font>", pAika);
					}
					else if (g_bInBonus[client])
					{
						// In Bonus
						Format(module[i], 128, "<font color='#d87'>%s       </font>", pAika);
					}
					else if (g_bMissedMapBest[client] && g_fPersonalStyleRecord[0][client] > 0.0)
					{
						// Missed Personal Best time
						Format(module[i], 128, "<font color='#f32'>%s       </font>", pAika);
					}
					else if (g_fPersonalStyleRecord[0][client] < 0.1)
					{
						// No Personal Best on map
						Format(module[i], 128, "<font color='#8cd'>%s       </font>", pAika);
					}
					else
					{
						// Hasn't missed Personal Best yet
						Format(module[i], 128, "<font color='#5e5'>%s       </font>", pAika);
					}
				}
				else if (g_bWrcpTimeractivated[client] && !g_bPracticeMode[client])
				{
					FormatTimeFloat(client, g_fCurrentWrcpRunTime[client], 3, pAika, 128);
					Format(module[i], 128, "<font color='#b8b'>%s       </font>", pAika);
				}
				else if (!g_bTimerEnabled[client])
					Format(module[i], 128, "<font color='#ec8'>Disabled       </font>");
				else
				{
					Format(module[i], 128, "<font color='#f32'>00:00:00       </font>");
				}

				if (g_iCurrentStyle[client] != 0)
				{
					switch (g_iCurrentStyle[client])
					{
						case 1: Format(module[i], 128, "SW %s", module[i]);
						case 2: Format(module[i], 128, "HSW %s", module[i]);
						case 3: Format(module[i], 128, "BW %s", module[i]);
						case 4: Format(module[i], 128, "LG %s", module[i]);
						case 5: Format(module[i], 128, "SM %s", module[i]);
						case 6: Format(module[i], 128, "FF %s", module[i]);
						case 7: Format(module[i], 128, "FS %s", module[i]);
					}
				}
			}
			else if (g_iCentreHudModule[client][i] == 2)
			{
				// server records (change from WR)
				if (gametime - g_fLastDifferenceTime[client] > 5.0)
				{
					if (g_iClientInZone[client][2] == 0) // Styles
					{
						if (g_fRecordStyleMapTime[style] != 9999999.0)
						{
							Format(g_szLastSRDifference[client], 64, "SR: %s", g_szRecordStyleMapTime[style]);
						}
						else
							Format(g_szLastSRDifference[client], 64, "SR: N/A");
					}
					else
					{
						Format(g_szLastSRDifference[client], 64, "SR: %s", g_szStyleBonusFastestTime[style][g_iClientInZone[client][2]]);
					}
				}
				Format(module[i], 128, "%s", g_szLastSRDifference[client]);
			}
			else if (g_iCentreHudModule[client][i] == 3)
			{
				// PB
				if (gametime - g_fLastDifferenceTime[client] > 5.0)
				{
					if (g_iClientInZone[client][2] == 0) // Styles
					{
						if (g_fRecordStyleMapTime[style] != 9999999.0)
						{
							if (g_fPersonalStyleRecord[style][client] > 0.0)
								Format(g_szLastPBDifference[client], 64, "PB: %s", g_szPersonalStyleRecord[style][client]);
							else
								Format(g_szLastPBDifference[client], 64, "PB: N/A");
						}
						else
							Format(g_szLastPBDifference[client], 64, "PB: N/A");
					}
					else
					{
						Format(g_szLastPBDifference[client], 64, "PB: %s", g_szStylePersonalRecordBonus[style][g_iClientInZone[client][2]][client]);
					}
				}
				Format(module[i], 128, "%s", g_szLastPBDifference[client]);
			}
			else if (g_iCentreHudModule[client][i] == 4)
			{
				// Rank Display
				char szRank[32];
				if (g_iClientInZone[client][2] > 0) // if in bonus stage, get bonus times
				{
					if (g_iCurrentStyle[client] == 0) // Normal
					{
						if (g_fStylePersonalRecordBonus[0][g_iClientInZone[client][2]][client] > 0.0)
							Format(szRank, 64, "Rank: %i / %i", g_StyleMapRankBonus[0][g_iClientInZone[client][2]][client], g_iStyleBonusCount[0][g_iClientInZone[client][2]]);
						else
							if (g_iStyleBonusCount[0][g_iClientInZone[client][2]] > 0)
								Format(szRank, 64, "Rank: - / %i", g_iStyleBonusCount[0][g_iClientInZone[client][2]]);
							else
								Format(szRank, 64, "Rank: N/A");
					}
					else if (g_iCurrentStyle[client] != 0) // Styles
					{
						if (g_fStylePersonalRecordBonus[style][g_iClientInZone[client][2]][client] > 0.0)
							Format(szRank, 64, "Rank: %i / %i", g_StyleMapRankBonus[style][g_iClientInZone[client][2]][client], g_iStyleBonusCount[style][g_iClientInZone[client][2]]);
						else
							if (g_iStyleBonusCount[style][g_iClientInZone[client][2]] > 0)
								Format(szRank, 64, "Rank: - / %i", g_iStyleBonusCount[style][g_iClientInZone[client][2]]);
							else
								Format(szRank, 64, "Rank: N/A");
					}
				}
				else // if in normal map, get normal times
				{
					if (g_iCurrentStyle[client] == 0) // Normal
					{
						if (g_fPersonalStyleRecord[0][client] > 0.0)
							Format(szRank, 64, "Rank: %i / %i", g_StyleMapRank[0][client], g_StyleMapTimesCount[0]);
						else
							if (g_StyleMapTimesCount[0] > 0)
								Format(szRank, 64, "Rank: - / %i", g_StyleMapTimesCount[0]);
							else
								Format(szRank, 64, "Rank: N/A");
					}
					else if (g_iCurrentStyle[client] != 0) // Styles
					{
						if (g_fPersonalStyleRecord[style][client] > 0.0)
							Format(szRank, 64, "Rank: %i / %i", g_StyleMapRank[style][client], g_StyleMapTimesCount[style]);
						else
							if (g_StyleMapTimesCount[style] > 0)
								Format(szRank, 64, "Rank: - / %i", g_StyleMapTimesCount[style]);
							else
								Format(szRank, 64, "Rank: N/A");
					}
				}

				Format(module[i], 128, "%s", szRank);
			}
			else if (g_iCentreHudModule[client][i] == 5)
			{
				// Stage Display
				if (g_iClientInZone[client][2] == 0)
				{
					if (!g_bhasStages) // map is linear
					{
						Format(module[i], 128, "Linear");
					}
					else // map has stages
					{
						Format(module[i], 128, "Stage: %i / %i", g_Stage[g_iClientInZone[client][2]][client], (g_mapZonesTypeCount[g_iClientInZone[client][2]][3] + 1)); // less \t's to make lines align
					}
				}
				else
					Format(module[i], 128, "Bonus %i", g_iClientInZone[client][2]);
			}
			else if (g_iCentreHudModule[client][i] == 6)
			{
				// Speed Display
				GetSpeedColour(client, RoundToNearest(g_fLastSpeed[client]), g_SpeedGradient[client]);
				if (RoundToNearest(g_fLastSpeed[client]) < 10 && RoundToNearest(g_fLastSpeed[client]) > -1)
				{
					if (i == 0 || i == 2 || i == 4)
						Format(module[i], 128, "Speed: <font color='%s'>%i</font> u/s       ", g_szSpeedColour[client], RoundToNearest(g_fLastSpeed[client]));
					else
						Format(module[i], 128, "Speed: <font color='%s'>%i</font> u/s", g_szSpeedColour[client], RoundToNearest(g_fLastSpeed[client]));
				}
				else
					Format(module[i], 128, "Speed: <font color='%s'>%i</font> u/s", g_szSpeedColour[client], RoundToNearest(g_fLastSpeed[client]));
			}
			else if (g_iCentreHudModule[client][i] == 7)
			{
				// Strafe Sync
				Format(module[i], 128, "Sync: %.02f%%", GetStrafeSync(client, true));
			}
		}

		// if (g_iCurrentStyle[client] > 0)
		// 	Format(timerText, sizeof(timerText), "%s%s", g_szStyleHud[client], timerColour);
		// else
		// 	Format(timerText, sizeof(timerText), "%s", timerColour);

		if (IsValidEntity(client) && 1 <= client <= MaxClients && !g_bOverlay[client])
		{
			// PrintCSGOHUDText(client, "<pre class='fontSize-sm'>%s%s\n%s%s\n%s%s</pre>", module[0], module2, module[2], module4, module[4], module6);
			PrintCSGOHUDText(client, "<pre class='fontSize-sm'>%15s\t %15s\n%15s\t %15s\n%15s\t %15s</pre>", module[0], module[1], module[2], module[3], module[4], module[5]);
		}
	}
}

public void SideHudAlive(int client)
{
	if (!IsValidClient(client) || IsFakeClient(client) || GetClientMenu(client) != MenuSource_None)
		return;

	if (g_bSideHud[client])
	{
		char szPanel[1280], szBuffer[2][256], szModule[5][1280];
		int style = g_iCurrentStyle[client];
		int moduleCount = 0;

		for (int i = 0; i < 5; i++)
		{
			if (g_iSideHudModule[client][i] != 0)
				moduleCount++;
		}

		for (int i = 0; i < 5; i++)
		{
			if (g_iSideHudModule[client][i] == 0)
			{
				Format(szModule[i], 256, "");
			}
			if (g_iSideHudModule[client][i] == 1)
			{
				int timeleft;
				GetMapTimeLeft(timeleft);
				int mins = timeleft / 60;
				int secs = timeleft % 60;

				if (mins > 0)
					Format(szModule[i], 256, "Timeleft: %d mins", mins);
				else
					Format(szModule[i], 256, "Timeleft: %d secs", secs);

				if ((i + 1) != moduleCount)
					Format(szModule[i], 256, "%s\n \n", szModule[i]);
			}
			else if (g_iSideHudModule[client][i] == 2)
			{
				char szWR[128];
				if (StrContains(g_szLastSRDifference[client], "<font") != -1)
				{
					ExplodeString(g_szLastSRDifference[client], ">", szBuffer, 2, 128);
					ExplodeString(szBuffer[1], "<", szBuffer, 2, 128);
					Format(szWR, 128, "SR: %s", szBuffer[0]);
				}
				else
					Format(szWR, 128, "%s", g_szLastSRDifference[client]);
				char szWRHolder[64];
				
				if (g_iClientInZone[client][2] == 0)
					Format(szWRHolder, sizeof(szWRHolder), g_szRecordStylePlayer[0]);
				else
					Format(szWRHolder, sizeof(szWRHolder), g_szStyleBonusFastest[0][g_iClientInZone[client][2]]);
				
				/*
												????
				else
				{
					if (g_iClientInZone[client][2] == 0)
						Format(szWRHolder, sizeof(szWRHolder), g_szRecordStylePlayer[0]);
					else
						Format(szWRHolder, sizeof(szWRHolder), g_szStyleBonusFastest[0][g_iClientInZone[client][2]]);
				}
				*/

				Format(szModule[i], 256, "%s\nby %s", szWR, szWRHolder);

				if ((i + 1) != moduleCount)
					Format(szModule[i], 256, "%s\n \n", szModule[i]);
			}
			else if (g_iSideHudModule[client][i] == 3)
			{
				char szPB[128];
				if (StrContains(g_szLastPBDifference[client], "<font") != -1)
				{
					ExplodeString(g_szLastPBDifference[client], ">", szBuffer, 2, 128);
					ExplodeString(szBuffer[1], "<", szBuffer, 2, 128);
					Format(szPB, sizeof(szPB), "PB: %s", szBuffer[0]);
				}
				else
					Format(szPB, sizeof(szPB), g_szLastPBDifference[client]);

				// Rank Display
				char szRank[32];
				if (g_iClientInZone[client][2] > 0) // if in bonus stage, get bonus times
				{
					if (g_iCurrentStyle[client] == 0) // Normal
					{
						if (g_fStylePersonalRecordBonus[0][g_iClientInZone[client][2]][client] > 0.0)
							Format(szRank, 64, "Rank: %i / %i", g_StyleMapRankBonus[0][g_iClientInZone[client][2]][client], g_iStyleBonusCount[0][g_iClientInZone[client][2]]);
						else
							if (g_iStyleBonusCount[0][g_iClientInZone[client][2]] > 0)
								Format(szRank, 64, "Rank: - / %i", g_iStyleBonusCount[0][g_iClientInZone[client][2]]);
							else
								Format(szRank, 64, "Rank: N/A");
					}
					else if (g_iCurrentStyle[client] != 0) // Styles
					{
						if (g_fStylePersonalRecordBonus[style][g_iClientInZone[client][2]][client] > 0.0)
							Format(szRank, 64, "Rank: %i / %i", g_StyleMapRankBonus[style][g_iClientInZone[client][2]][client], g_iStyleBonusCount[style][g_iClientInZone[client][2]]);
						else
							if (g_iStyleBonusCount[style][g_iClientInZone[client][2]] > 0)
								Format(szRank, 64, "Rank: - / %i", g_iStyleBonusCount[style][g_iClientInZone[client][2]]);
							else
								Format(szRank, 64, "Rank: N/A");
					}
				}
				else // if in normal map, get normal times
				{
					if (g_iCurrentStyle[client] == 0) // Normal
					{
						if (g_fPersonalStyleRecord[0][client] > 0.0)
							Format(szRank, 64, "Rank: %i / %i", g_StyleMapRank[0][client], g_StyleMapTimesCount[0]);
						else
							if (g_StyleMapTimesCount[0] > 0)
								Format(szRank, 64, "Rank: - / %i", g_StyleMapTimesCount[0]);
							else
								Format(szRank, 64, "Rank: N/A");
					}
					else if (g_iCurrentStyle[client] != 0) // Styles
					{
						if (g_fPersonalStyleRecord[style][client] > 0.0)
							Format(szRank, 64, "Rank: %i / %i", g_StyleMapRank[style][client], g_StyleMapTimesCount[style]);
						else
							if (g_StyleMapTimesCount[style] > 0)
								Format(szRank, 64, "Rank: - / %i", g_StyleMapTimesCount[style]);
							else
								Format(szRank, 64, "Rank: N/A");
					}
				}

				Format(szModule[i], 256, "%s\n%s", szPB, szRank);

				if ((i + 1) != moduleCount)
					Format(szModule[i], 256, "%s\n \n", szModule[i]);
			}
			else if (g_iSideHudModule[client][i] == 4)
			{
				int stage = g_Stage[g_iClientInZone[client][2]][client];

				// Stage Display
				char szStage[64];
				if (g_iClientInZone[client][2] == 0)
				{
					if (!g_bhasStages) // map is linear
					{
						// Format(szStage, 64, "Linear");
						char szCP[64];
						char szCurrentCP[64];
						if (g_iCurrentCheckpoint[client] == g_mapZonesTypeCount[g_iClientInZone[client][2]][4])
						{
							FormatTimeFloat(0, g_fRecordStyleMapTime[0], 3, szCP, 64);
							Format(szCurrentCP, 64, "End Zone");
						}
						else
						{
							Format(szCurrentCP, 64, "Checkpoint [%i]", g_iCurrentCheckpoint[client] + 1);
							FormatTimeFloat(0, g_fCheckpointServerRecord[g_iClientInZone[client][2]][g_iCurrentCheckpoint[client]], 3, szCP, 64);
						}

						Format(szModule[i], 256, "%s\n%s", szCurrentCP, szCP);

						if ((i + 1) != moduleCount)
							Format(szModule[i], 256, "%s\n \n", szModule[i]);
					}
					else // map has stages
					{
						Format(szStage, 64, "Stage: %i / %i", g_Stage[g_iClientInZone[client][2]][client], (g_mapZonesTypeCount[g_iClientInZone[client][2]][3] + 1));
						char szWrcpTime[64];
						FormatTimeFloat(0, g_fStyleStageRecord[0][stage], 3, szWrcpTime, 64);
						char szName[64];
						Format(szName, 64, "%s", g_szStyleStageRecordPlayer[0][stage]);
						Format(szModule[i], 256, "%s\nSRCP: %s\nby %s", szStage, szWrcpTime, szName);

						if ((i + 1) != moduleCount)
							Format(szModule[i], 256, "%s\n \n", szModule[i]);
					}
				}
				else
				{
					Format(szModule[i], 256, "", szStage);
				}

			}
			else if (g_iSideHudModule[client][i] == 5)
			{
				char sSpecs[512];
				char szSpecList[512];
				int SpecMode;
				Format(sSpecs, 512, "");
				Format(szSpecList, 512, "Specs (0)");
				int count = 0;
				for (int j = 0; j <= MaxClients; j++)
				{
					if (IsValidClient(j) && !IsFakeClient(client) && !IsPlayerAlive(j) && !g_bFirstTeamJoin[j] && g_bSpectate[j] && !g_iSilentSpectate[j])
					{
						SpecMode = GetEntProp(j, Prop_Send, "m_iObserverMode");
						if (SpecMode == 4 || SpecMode == 5)
						{
							int Target;
							Target = GetEntPropEnt(j, Prop_Send, "m_hObserverTarget");
							if (Target == client)
							{
								count++;
								if (count < 6)
									Format(sSpecs, 512, "%s%N\n", sSpecs, j);

							}
							if (count == 6)
								Format(sSpecs, 512, "%s...", sSpecs);
						}
					}
				}
				if (count > 0)
					Format(szSpecList, 512, "Specs (%i):\n%s ", count, sSpecs);
				else
					Format(szSpecList, 512, "Specs (0)");

				Format(szModule[i], 256, "%s", szSpecList);

				if ((i + 1) != moduleCount)
					Format(szModule[i], 256, "%s\n \n", szModule[i]);
			}
		}

		Format(szPanel, sizeof(szPanel), "%s%s%s%s%s", szModule[0], szModule[1], szModule[2], szModule[3], szModule[4]);
		Handle panel = CreatePanel();
		DrawPanelText(panel, szPanel);

		SendPanelToClient(panel, client, PanelHandler, 1);
		delete panel;
	}
}

public void Checkpoint(int client, int zone, int zonegroup, float time, int speed[3])
{
	if (!IsValidClient(client) || g_bPositionRestored[client] || IsFakeClient(client) || zone >= CPLIMIT)
		return;

	// int speedType = g_SpeedMode[client];
	int speedType = 1;

	if (g_mapZones[zone].PreSpeed > 250.0 || !g_bhasStages)
		speedType = 0;
	else
		speedType = 1;

	// float time = g_fCurrentRunTime[client];
	float percent = -1.0;
	int totalPoints = 0;
	char szPercnt[24];
	char szSpecMessage[512];

	if (g_bhasStages) // If staged map
		totalPoints = g_mapZonesTypeCount[zonegroup][3];
	else
		if (g_mapZonesTypeCount[zonegroup][4] > 0) // If Linear Map and checkpoints
		totalPoints = g_mapZonesTypeCount[zonegroup][4];

	// Count percent of completion
	percent = (float(zone + 1) / float(totalPoints + 1));
	percent = percent * 100.0;
	Format(szPercnt, 24, "%1.f%%", percent);

	if (g_bTimerRunning[client] && !g_bPracticeMode[client]) {
		if (g_fMaxPercCompleted[client] < 1.0) // First time a checkpoint is reached
			g_fMaxPercCompleted[client] = percent;
		else
			if (g_fMaxPercCompleted[client] < percent) // The furthest checkpoint reached
			g_fMaxPercCompleted[client] = percent;
	}

	g_fCheckpointTimesNew[zonegroup][client][zone] = time;

	for (int i = 0; i < 3; i++)
	{
		g_iCheckpointVelsEndNew[zonegroup][client][zone][i] = speed[i];
	}

	// Server record difference
	char sz_srDiff[128];
	char sz_srDiff_colorless[128];

	char sz_srDiffVel[128];
	char sz_srDiffVel_colorless[128];

	if (g_bCheckpointRecordFound[zonegroup] && g_fCheckpointServerRecord[zonegroup][zone] > 0.1 && g_bTimerRunning[client])
	{
		float f_srDiff = (g_fCheckpointServerRecord[zonegroup][zone] - time);
		FormatTimeFloat(client, f_srDiff, 3, sz_srDiff, 128);

		if (f_srDiff > 0)
		{
			Format(sz_srDiff_colorless, 128, "-%s", sz_srDiff);
			Format(sz_srDiff, 128, "%cSR: %c-%s%c", WHITE, LIGHTGREEN, sz_srDiff, WHITE);
			if (zonegroup > 0)
				Format(g_szLastSRDifference[client], 64, "SR: %s", sz_srDiff_colorless);
			else
				Format(g_szLastSRDifference[client], 64, "SR: %s", sz_srDiff_colorless);

		}
		else
		{
			Format(sz_srDiff_colorless, 128, "+%s", sz_srDiff);
			Format(sz_srDiff, 128, "%cSR: %c+%s%c", WHITE, RED, sz_srDiff, WHITE);
			if (zonegroup > 0)
				Format(g_szLastSRDifference[client], 64, "SR: %s", sz_srDiff_colorless);
			else if (g_iCurrentStyle[client] > 0)
				Format(g_szLastSRDifference[client], 64, "\tSR: %s", sz_srDiff_colorless);
			else
				Format(g_szLastSRDifference[client], 64, "SR: %s", sz_srDiff_colorless);
		}
		g_fLastDifferenceTime[client] = GetGameTime();
	}
	else
		Format(sz_srDiff, 128, "%cSR: %cN/A%c", WHITE, LIGHTGREEN, WHITE);


	// Get client name for spectators
	char szName[MAX_NAME_LENGTH];
	GetClientName(client, szName, MAX_NAME_LENGTH);

	// Has completed the map before
	if (g_bCheckpointsFound[zonegroup][client] && g_bTimerRunning[client] && !g_bPracticeMode[client] && g_fCheckpointTimesRecord[zonegroup][client][zone] > 0.1)
	{
		// Set percent of completion to assist
		if (CS_GetMVPCount(client) < 1)
			CS_SetClientAssists(client, RoundToFloor(g_fMaxPercCompleted[client]));
		else
			CS_SetClientAssists(client, 100);

		// Own record difference
		float diff = (g_fCheckpointTimesRecord[zonegroup][client][zone] - time);
		char szDiff[32];
		char szDiff_colorless[32];

		FormatTimeFloat(client, diff, 3, szDiff, 32);

		// MOVE TO PB variable
		if (diff > 0)
		{
			Format(szDiff_colorless, 32, "-%s", szDiff);
			Format(szDiff, sizeof(szDiff), "%c-%s", LIGHTGREEN, szDiff);
			if (zonegroup > 0)
				Format(g_szLastPBDifference[client], 64, "PB: <font color='#5e5'>%s</font>", szDiff_colorless);
			else
				Format(g_szLastPBDifference[client], 64, "PB: <font color='#5e5'>%s</font>", szDiff_colorless);

			/*
			if (zonegroup > 0)
				Format(g_szLastPBDifference[client], 64, "%s <font color='#99ff99' size='16'>%s</font>", g_szStylePersonalRecordBonus[0][zonegroup][client], szDiff_colorless);
			else
				Format(g_szLastPBDifference[client], 64, "%s <font color='#99ff99' size='16'>%s</font>", g_szPersonalStyleRecord[0][client], szDiff_colorless);
				*/
		}
		else
		{
			Format(szDiff_colorless, 32, "+%s", szDiff);
			Format(szDiff, sizeof(szDiff), "%c+%s", RED, szDiff);
			if (zonegroup > 0)
				Format(g_szLastPBDifference[client], 64, "PB: <font color='#f32'>%s</font>", szDiff_colorless);
			else
				Format(g_szLastPBDifference[client], 64, "PB: <font color='#f32'>%s</font>", szDiff_colorless);
			/*
			if (zonegroup > 0)
				Format(g_szLastPBDifference[client], 64, "%s <font color='#FF9999' size='16'>%s</font>", g_szStylePersonalRecordBonus[0][zonegroup][client], szDiff_colorless);
			else
				Format(g_szLastPBDifference[client], 64, "%s <font color='#FF9999' size='16'>%s</font>", g_szPersonalStyleRecord[0][client], szDiff_colorless);
			*/
		}
		g_fLastDifferenceTime[client] = GetGameTime();

		// Velocity Difference
		char szDiffVel[128];
		char szDiffVel_colorless[128];
		char szStartWR[256], szStartPB[256];
		char szEnd[256];
		char szEndWR[256];
		int diffVel, savedSpeed, currentSpeed;

		// FormatTimeFloat(client, diffVel, 3, szDiffVel, 32);

		// // MOVE TO PB variable
		//ShowVelocityPB
		//"en"		"{1} Start: 0 u/s [PB +0 u/s] | {2}: {3} [PB {4} u/s]"

		// WR Start Speed
		int startSpeedDiffWR, startSpeedDiffPB;
		int compare, compare2;
		if (zone == 0)
		{
			speedType = 1;
			compare = g_iStartVelsServerRecord[0][1];
			compare2 = g_iStartVelsNew[client][0][1];
		}
		else
		{
			if (g_mapZones[zone].PreSpeed > 250.0 || !g_bhasStages)
				speedType = 0;
			else
				speedType = 1;

			compare = g_iCheckpointVelsStartServerRecord[zonegroup][zone - 1][speedType];
			compare2 = g_iCheckpointVelsStartNew[zonegroup][client][zone - 1][speedType];
		}

		if (compare == 0)
			startSpeedDiffWR = compare2;
		else if (compare > compare2)
			startSpeedDiffWR = (compare - compare2);
		else
			startSpeedDiffWR = (compare2 - compare);

		if (compare2 > compare)
			Format(szStartWR, sizeof(szStartWR), "+%d", startSpeedDiffWR);
		else
			Format(szStartWR, sizeof(szStartWR), "-%d", startSpeedDiffWR);


		// WR End Speed
		int f_srDiffVel;
		if (g_iCheckpointVelsEndServerRecord[zonegroup][zone][speedType] == 0)
			f_srDiffVel = speed[speedType];
		else if (g_iCheckpointVelsEndServerRecord[zonegroup][zone][speedType] > speed[speedType])
			f_srDiffVel = (g_iCheckpointVelsEndServerRecord[zonegroup][zone][speedType] - speed[speedType]);
		else
			f_srDiffVel = (speed[speedType] - g_iCheckpointVelsEndServerRecord[zonegroup][zone][speedType]);

		int srDiffVel = f_srDiffVel;
		if (speed[speedType] > g_iCheckpointVelsEndServerRecord[zonegroup][zone][speedType] || g_iCheckpointVelsEndServerRecord[zonegroup][zone][speedType] == 0)
		{
			Format(sz_srDiffVel_colorless, 128, "+%d", srDiffVel);
			Format(sz_srDiffVel, 128, "%s", sz_srDiffVel_colorless);
			Format(szEndWR, sizeof(szEndWR), sz_srDiffVel);
		}
		else
		{
			Format(sz_srDiffVel_colorless, 128, "-%d", srDiffVel);
			Format(sz_srDiffVel, 128, "%s", sz_srDiffVel_colorless);
			Format(szEndWR, sizeof(szEndWR), sz_srDiffVel);
		}

		// PB Start Speed
		if (zone == 0)
		{
			compare = g_iStartVelsRecord[client][0][speedType];
			compare2 = g_iStartVelsNew[client][0][speedType];
		}
		else
		{
			compare = g_iCheckpointVelsStartRecord[zonegroup][client][zone - 1][speedType];
			compare2 = g_iCheckpointVelsStartNew[zonegroup][client][zone - 1][speedType];
		}

		if (compare == 0)
			startSpeedDiffPB = compare2;
		else if (compare > compare2)
			startSpeedDiffPB = (compare - compare2);
		else
			startSpeedDiffPB = (compare2 - compare);

		if (compare2 > compare)
			Format(szStartPB, sizeof(szStartPB), "+%d", startSpeedDiffPB);
		else
			Format(szStartPB, sizeof(szStartPB), "-%d", startSpeedDiffPB);

		// PB End Speed

		savedSpeed = g_iCheckpointVelsEndRecord[zonegroup][client][zone][speedType];
		currentSpeed = speed[speedType];

		if (savedSpeed == 0)
			diffVel = currentSpeed;
		else if (savedSpeed > currentSpeed)
			diffVel = (savedSpeed - currentSpeed);
		else
			diffVel = (currentSpeed - savedSpeed);

		int iDiffVel = diffVel;
		if (currentSpeed > savedSpeed || savedSpeed == 0)
		{
			Format(szDiffVel_colorless, 128, "+%d", iDiffVel);
			Format(szDiffVel, 128, "%s", szDiffVel_colorless);
			Format(szEnd, sizeof(szEnd), szDiffVel);
			// Format(szDiff, 128, "%s%s", szDiff, szDiffVel);
		}
		else
		{
			Format(szDiffVel_colorless, 128, "%d", iDiffVel);
			Format(szDiffVel, 128, "-%s", szDiffVel_colorless);
			Format(szEnd, sizeof(szEnd), szDiffVel);
			// Format(szDiff, 128, "%s%s", szDiff, szDiffVel);
		}

		if (g_fCheckpointTimesRecord[zonegroup][client][zone] <= 0.0)
			Format(szDiff, 128, "");

		char szTime[32];
		FormatTimeFloat(client, time, 3, szTime, 32);

		// Checkpoint forward
		//forward Action:surftimer_OnCheckpoint(client, Float:fRunTime, String:sRunTime[54], Float:fPbCp, String:sPbDiff[16], Float:fSrCp, String:sSrDiff[16]);
		Call_StartForward(g_MapCheckpointForward);

		/* Push parameters one at a time */
		Call_PushCell(client);
		Call_PushFloat(time);
		Call_PushString(szTime);
		Call_PushFloat(g_fCheckpointTimesRecord[zonegroup][client][zone]);
		Call_PushString(szDiff_colorless);
		Call_PushFloat(g_fCheckpointServerRecord[zonegroup][zone]);
		Call_PushString(sz_srDiff_colorless);

		/* Finish the call, get the result */
		Call_Finish();

		if (g_bCheckpointsEnabled[client])
		{
			CPrintToChat(client, "%t", "Misc30", g_szChatPrefix, g_iClientInZone[client][1] + 1, szTime, szDiff, sz_srDiff);
			// if velocity setting enabled
			//ShowVelocityPB
			// "#format"	"{1:s},{2:i},{3:s},{4:s},{5:i},{6:i},{7:s},{8:s}"
			// "en"		"{1} Start: {yellow}{2} u/s {default}[WR {3} {default}| PB {4}{default}] | {5}: {yellow}{6} {default}[WR {7} {default}| PB {8}{default}]"
			int startSpeed;
			if (zone == 0)
				startSpeed = g_iStartVelsNew[client][0][speedType];
			else
				startSpeed = g_iCheckpointVelsStartNew[zonegroup][client][zone - 1][speedType];

			CPrintToChat(client, "%t", "ShowVelocityCP", g_szChatPrefix, startSpeed, szStartWR, szStartPB, (g_bhasStages ? "End" : "Touch"), speed[speedType], szEndWR, szEnd);
		}

		Format(szSpecMessage, sizeof(szSpecMessage), "%t", "Misc31", g_szChatPrefix, szName, g_iClientInZone[client][1] + 1, szTime, szDiff, sz_srDiff);
		CheckpointToSpec(client, szSpecMessage);

		// Saving difference time for next checkpoint
		tmpDiff[client] = diff;
	}
	else // if first run
		if (g_bTimerRunning[client] && !g_bPracticeMode[client])
		{
			char szStartWR[256];
			char szEndWR[256];
			// WR Start Speed
			int startSpeedDiffWR;
			int compare, compare2;
			if (zone == 0)
			{
				speedType = 1;
				compare = g_iStartVelsServerRecord[0][speedType];
				compare2 = g_iStartVelsNew[client][0][speedType];
			}
			else
			{
				if (g_mapZones[zone].PreSpeed > 250.0)
					speedType = 0;
				else
					speedType = 1;

				compare = g_iCheckpointVelsStartServerRecord[zonegroup][zone - 1][speedType];
				compare2 = g_iCheckpointVelsStartNew[zonegroup][client][zone - 1][speedType];
			}

			if (compare == 0)
				startSpeedDiffWR = compare2;
			else if (compare > compare2)
				startSpeedDiffWR = (compare - compare2);
			else
				startSpeedDiffWR = (compare2 - compare);

			if (compare2 > compare)
				Format(szStartWR, sizeof(szStartWR), "+%d", startSpeedDiffWR);
			else
				Format(szStartWR, sizeof(szStartWR), "-%d", startSpeedDiffWR);


			// WR End Speed
			int f_srDiffVel;
			if (g_iCheckpointVelsEndServerRecord[zonegroup][zone][speedType] == 0)
				f_srDiffVel = speed[speedType];
			else
				f_srDiffVel = (g_iCheckpointVelsEndServerRecord[zonegroup][zone][speedType] - speed[speedType]);

			int srDiffVel = f_srDiffVel;
			if (speed[speedType] > g_iCheckpointVelsEndServerRecord[zonegroup][zone][speedType] || g_iCheckpointVelsEndServerRecord[zonegroup][zone][speedType] == 0)
			{
				Format(sz_srDiffVel_colorless, 128, "+%d", srDiffVel);
				Format(sz_srDiffVel, 128, "%s", sz_srDiffVel_colorless);
				Format(szEndWR, sizeof(szEndWR), sz_srDiffVel);
			}
			else
			{
				Format(sz_srDiffVel_colorless, 128, "-%d", srDiffVel);
				Format(sz_srDiffVel, 128, "%s", sz_srDiffVel_colorless);
				Format(szEndWR, sizeof(szEndWR), sz_srDiffVel);
			}

			int startSpeed;
			if (zone == 0)
				startSpeed = g_iStartVelsNew[client][0][speedType];
			else
				startSpeed = g_iCheckpointVelsStartNew[zonegroup][client][zone - 1][speedType];

			CPrintToChat(client, "%t", "ShowVelocityCP", g_szChatPrefix, startSpeed, szStartWR, "N/A", (g_bhasStages ? "End" : "Touch"), speed[speedType], szEndWR, "N/A");
			// Set percent of completion to assist
			if (CS_GetMVPCount(client) < 1)
				CS_SetClientAssists(client, RoundToFloor(g_fMaxPercCompleted[client]));
			else
				CS_SetClientAssists(client, 100);

			char szTime[32];
			FormatTimeFloat(client, time, 3, szTime, 32);

			Call_StartForward(g_MapCheckpointForward);

			/* Push parameters one at a time */
			Call_PushCell(client);
			Call_PushFloat(time);
			Call_PushString(szTime);
			Call_PushFloat(-1.0);
			Call_PushString("N/A");
			Call_PushFloat(g_fCheckpointServerRecord[zonegroup][zone]);
			Call_PushString(sz_srDiff_colorless);

			/* Finish the call, get the result */
			Call_Finish();

			if (percent > -1.0)
			{
				if (g_bCheckpointsEnabled[client])
					CPrintToChat(client, "%t", "Misc32", g_szChatPrefix, g_iClientInZone[client][1] + 1, szTime, sz_srDiff);

				Format(szSpecMessage, sizeof(szSpecMessage), "%t", "Misc33", g_szChatPrefix, szName, g_iClientInZone[client][1] + 1, szTime, sz_srDiff);
				CheckpointToSpec(client, szSpecMessage);
			}
		}
}

public void CheckpointToSpec(int client, char[] buffer)
{
	int SpecMode;
	for (int x = 1; x <= MaxClients; x++)
	{
		if (IsValidClient(x) && !IsPlayerAlive(x))
		{
			SpecMode = GetEntProp(x, Prop_Send, "m_iObserverMode");
			if (SpecMode == 4 || SpecMode == 5)
			{
				int Target = GetEntPropEnt(x, Prop_Send, "m_hObserverTarget");
				if (Target == client && g_iCpMessages[x])
					CPrintToChat(x, "%s", buffer);
			}
		}
	}
}

public void ResetGravity(int client)
{
	if (IsValidClient(client) && !IsFakeClient(client))
	{
		float gravity = GetEntityGravity(client);
		if (g_iCurrentStyle[client] != 4)
		{
			if (gravity != 1.0)
				SetEntityGravity(client, 1.0);
		}
		else
			SetEntityGravity(client, 0.5);
	}
}

stock void StyleFinishedMsgs(int client, int style)
{
	if (IsValidClient(client))
	{
		float RecordDiff, RecordDiff2;
		char szRecordDiff[32], szRecordDiff2[32], szName[MAX_NAME_LENGTH];
		GetClientName(client, szName, MAX_NAME_LENGTH);
		int count = g_StyleMapTimesCount[style];

		// Map style SR, time difference formatting
		RecordDiff = g_fRecordStyleMapTime[style] - g_fFinalTime[client];
		FormatTimeFloat(client, RecordDiff, 3, szRecordDiff, 32);
		if (RecordDiff > 0.0)
		{
			Format(szRecordDiff, 32, "+%s", szRecordDiff);
		}
		else
		{
			Format(szRecordDiff, 32, "-%s", szRecordDiff);
		}

		// Player beat map style SR, time difference formatting
		RecordDiff2 = g_fOldRecordStyleMapTime[style] - g_fFinalTime[client];
		FormatTimeFloat(client, RecordDiff2, 3, szRecordDiff2, 32);
		if (RecordDiff2 > 0.0)
		{
			Format(szRecordDiff2, 32, "-%s", szRecordDiff2);
		}
		else
		{
			Format(szRecordDiff2, 32, "+%s", szRecordDiff2);
		}
		
		if (GetConVarInt(g_hAnnounceRecord) == 0 || GetConVarInt(g_hAnnounceRecord) == 1)
		{
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsValidClient(i) && !IsFakeClient(i))
				{
					if (g_bStyleMapSRVRecord[style][client] && g_fFinalTime[client] == g_fOldRecordStyleMapTime[style]) // Player sets 1st Server Style Record
					{
						PlayRecordSound(2);
						
						CPrintToChat(i, "%t", "StyleFirstMapRecord", g_szChatPrefix, szName, g_szStyleRecordPrint[style]);
						PrintToConsole(client, "Surftimer | %s set the %s map record!", szName, g_szStyleRecordPrint[style]);

						CPrintToChat(i, "%t", "StyleMapFinished1", g_szChatPrefix, szName, g_szStyleRecordPrint[style], g_szFinalTime[client]);
						PrintToConsole(client, "Surftimer | %s set a %s SR of %s", szName, g_szStyleRecordPrint[style], g_szFinalTime[client]);
					}
					else if (g_bStyleMapSRVRecord[style][client]) // Player beat the Server Style Record
					{
						PlayRecordSound(2);
						
						CPrintToChat(i, "%t", "StyleNewMapRecord", g_szChatPrefix, szName, g_szStyleRecordPrint[style]);
						PrintToConsole(client, "Surftimer | %s beat the %s map record!", szName, g_szStyleRecordPrint[style]);
								
						CPrintToChat(i, "%t", "StyleMapFinished2", g_szChatPrefix, szName, g_szStyleRecordPrint[style], g_szFinalTime[client], szRecordDiff2, g_szTimeDifference[client], g_StyleMapRank[style][client], count);
						PrintToConsole(client, "Surftimer | %s finished %s in %s [SR %s | PB %s | Rank #%i/%i]", szName, g_szStyleRecordPrint[style], g_szFinalTime[client], szRecordDiff2, g_szTimeDifference[client], g_StyleMapRank[style][client], count);                                  
					}
					else if (g_bStyleMapFirstRecord[style][client] && !g_bStyleMapSRVRecord[style][client]) // Player 1st time finishing map using style
					{      
						CPrintToChat(i, "%t", "StyleMapFinished3", g_szChatPrefix, szName, g_szStyleRecordPrint[style], g_szFinalTime[client], szRecordDiff, g_StyleMapRank[style][client], count);
						PrintToConsole(client, "Surftimer | %s set a %s PB of %s [SR %s | Rank #%i/%i]", szName, g_szStyleRecordPrint[style], g_szFinalTime[client], szRecordDiff, g_StyleMapRank[style][client], count);
							
					}
					else if (g_bStyleMapPBRecord[style][client] && !g_bStyleMapSRVRecord[style][client]) // Player beat Personal Record using style
					{
						PlayUnstoppableSound(client);
						
						CPrintToChat(i, "%t", "StyleMapFinished4",g_szChatPrefix, szName, g_szStyleRecordPrint[style], g_szFinalTime[client], szRecordDiff, g_szTimeDifference[client], g_StyleMapRank[style][client], count);
						PrintToConsole(client, "Surftimer | %s finished %s in %s [SR %s | PB %s | Rank #%i/%i]", szName, g_szStyleRecordPrint[style], g_szFinalTime[client], szRecordDiff, g_szTimeDifference[client], g_StyleMapRank[style][client], count);

					}                                      
				}
			}
		}
		else if (GetConVarInt(g_hAnnounceRecord) == 2) // Print SR to all only. Still advise player of own times
		{
			for (int i = 1; i <= MaxClients; i++)
			{
				if (g_bStyleMapSRVRecord[style][client] && g_fFinalTime[client] == g_fOldRecordStyleMapTime[style]) // Player sets 1st Server Style Record
				{
					PlayRecordSound(2);
					
					CPrintToChat(i, "%t", "StyleFirstMapRecord", g_szChatPrefix, szName, g_szStyleRecordPrint[style]);
					PrintToConsole(client, "Surftimer | %s set the %s map record!", szName, g_szStyleRecordPrint[style]);

					CPrintToChat(i, "%t", "StyleMapFinished1", g_szChatPrefix, szName, g_szStyleRecordPrint[style], g_szFinalTime[client]);
					PrintToConsole(client, "Surftimer | %s set a %s SR of %s", szName, g_szStyleRecordPrint[style], g_szFinalTime[client]);
				}
				else if (g_bStyleMapSRVRecord[style][client]) // Player beat the Server Style Record
				{
					PlayRecordSound(2);
					
					CPrintToChat(i, "%t", "StyleNewMapRecord", g_szChatPrefix, szName, g_szStyleRecordPrint[style]);
					PrintToConsole(client, "Surftimer | %s beat the %s map record!", szName, g_szStyleRecordPrint[style]);
							
					CPrintToChat(i, "%t", "StyleMapFinished2", g_szChatPrefix, szName, g_szStyleRecordPrint[style], g_szFinalTime[client], szRecordDiff2, g_szTimeDifference[client], g_StyleMapRank[style][client], count);
					PrintToConsole(client, "Surftimer | %s finished %s in %s [SR %s | PB %s | Rank #%i/%i]", szName, g_szStyleRecordPrint[style], g_szFinalTime[client], szRecordDiff2, g_szTimeDifference[client], g_StyleMapRank[style][client], count);                                  
				}
				else if (g_bStyleMapFirstRecord[style][client] && !g_bStyleMapSRVRecord[style][client]) // Player 1st time finishing map using style
				{      
					CPrintToChat(client, "%t", "StyleMapFinished3", g_szChatPrefix, szName, g_szStyleRecordPrint[style], g_szFinalTime[client], szRecordDiff, g_StyleMapRank[style][client], count);
					PrintToConsole(client, "Surftimer | %s set a %s PB of %s [SR %s | Rank #%i/%i]", szName, g_szStyleRecordPrint[style], g_szFinalTime[client], szRecordDiff, g_StyleMapRank[style][client], count);
						
				}
				else if (g_bStyleMapPBRecord[style][client] && !g_bStyleMapSRVRecord[style][client]) // Player beat Personal Record using style
				{
					PlayUnstoppableSound(client);
					
					CPrintToChat(client, "%t", "StyleMapFinished4",g_szChatPrefix, szName, g_szStyleRecordPrint[style], g_szFinalTime[client], szRecordDiff, g_szTimeDifference[client], g_StyleMapRank[style][client], count);
					PrintToConsole(client, "Surftimer | %s finished %s in %s [SR %s | PB %s | Rank #%i/%i]", szName, g_szStyleRecordPrint[style], g_szFinalTime[client], szRecordDiff, g_szTimeDifference[client], g_StyleMapRank[style][client], count);

				}
			}
		}		
	}	             

	if (g_StyleMapRank[style][client] == 99999 && IsValidClient(client))
		CPrintToChat(client, "%t", "FailedSaveData", g_szChatPrefix);

	CalculatePlayerRank(client, style);
	return;
}

stock void PrintChatBonusStyle (int client, int zGroup, int style, int rank = 0)
{
	if (!IsValidClient(client))
	return;

	float RecordDiff, RecordDiff2;
	char szRecordDiff[54], szRecordDiff2[54], szName[MAX_NAME_LENGTH];

	if (rank == 0)
	rank = g_StyleMapRankBonus[style][zGroup][client];

	GetClientName(client, szName, MAX_NAME_LENGTH);

	// Bonus style SR, time difference formatting
	RecordDiff = g_fStyleBonusFastest[style][zGroup] - g_fFinalTime[client];
	FormatTimeFloat(client, RecordDiff, 3, szRecordDiff, 54);
	if (RecordDiff > 0.0)
	{
		Format(szRecordDiff, 54, "-%s", szRecordDiff);
	}
	else
	{
		Format(szRecordDiff, 54, "+%s", szRecordDiff);
	}

	// Player beat bonus style SR, time difference formatting
	RecordDiff2 = g_fStyleOldBonusRecordTime[style][zGroup] - g_fFinalTime[client];
	FormatTimeFloat(client, RecordDiff2, 3, szRecordDiff2, 54);
	if (RecordDiff2 > 0.0)
	{
		Format(szRecordDiff2, 54, "-%s", szRecordDiff2);
	}
	else
	{
		Format(szRecordDiff2, 54, "+%s", szRecordDiff2);
	}

	if (g_bBonusSRVRecord[client] && g_fFinalTime[client] == g_fStyleOldBonusRecordTime[style][zGroup]) // Player sets 1st bonus style record
	{
		PlayRecordSound(2);

		CPrintToChatAll("%t", "StyleFirstBonusRecord", g_szChatPrefix, szName, g_szZoneGroupName[zGroup], g_szStyleRecordPrint[style]);
		PrintToConsole(client, "Surftimer | %s set the %s %s record!", szName, g_szZoneGroupName[zGroup], g_szStyleRecordPrint[style]);

		CPrintToChatAll("%t", "StyleBonusFinished1", g_szChatPrefix, szName, g_szZoneGroupName[zGroup], g_szStyleRecordPrint[style], g_szFinalTime[client]);
		PrintToConsole(client, "Surftimer | %s set a %s %s SR of %s", szName, g_szZoneGroupName[zGroup], g_szStyleRecordPrint[style], g_szFinalTime[client]);
	}
	else if (g_bBonusSRVRecord[client]) // Player beats bonus style record
	{
		PlayRecordSound(2);
		
		CPrintToChatAll("%t", "StyleNewBonusRecord", g_szChatPrefix, szName, g_szZoneGroupName[zGroup], g_szStyleRecordPrint[style]);
		PrintToConsole(client, "Surftimer | %s beat the %s %s record!", szName, g_szZoneGroupName[zGroup], g_szStyleRecordPrint[style]);
			
		CPrintToChatAll("%t", "StyleBonusFinished2", g_szChatPrefix, szName, g_szZoneGroupName[zGroup], g_szStyleRecordPrint[style], g_szFinalTime[client], szRecordDiff2, g_szBonusTimeDifference[client], g_StyleMapRankBonus[style][zGroup][client], g_iStyleBonusCount[style][zGroup]);
		PrintToConsole(client, "Surftimer | %s finished %s %s in %s [SR %s | PB %s | Rank #%i/%i]", szName, g_szZoneGroupName[zGroup], g_szStyleRecordPrint[style], g_szFinalTime[client], szRecordDiff2, g_szBonusTimeDifference[client], g_StyleMapRankBonus[style][zGroup][client], g_iStyleBonusCount[style][zGroup]);
	}
	else if (g_bBonusFirstRecord[client] && !g_bBonusSRVRecord[client]) // Player 1st time finishing bonus using style
	{
		CPrintToChatAll("%t", "StyleBonusFinished3", g_szChatPrefix, szName, g_szZoneGroupName[zGroup], g_szStyleRecordPrint[style], g_szFinalTime[client], szRecordDiff, g_StyleMapRankBonus[style][zGroup][client], g_iStyleBonusCount[style][zGroup]);
		PrintToConsole(client, "Surftimer | %s set a %s %s PB of %s [SR %s | Rank #%i/%i]", szName, g_szZoneGroupName[zGroup], g_szStyleRecordPrint[style], g_szFinalTime[client], szRecordDiff, g_StyleMapRankBonus[style][zGroup][client], g_iStyleBonusCount[style][zGroup]);
	}
	else if (g_bBonusPBRecord[client] && !g_bBonusSRVRecord[client]) // Player beats PB but not bonus record using style
	{
		PlayUnstoppableSound(client);
		
		CPrintToChatAll("%t", "StyleBonusFinished4", g_szChatPrefix, szName, g_szZoneGroupName[zGroup], g_szStyleRecordPrint[style], g_szFinalTime[client], szRecordDiff, g_szBonusTimeDifference[client], g_StyleMapRankBonus[style][zGroup][client], g_iStyleBonusCount[style][zGroup]);
		PrintToConsole(client, "Surftimer | %s finished %s %s in %s [SR %s | PB %s | Rank #%i/%i]", szName, g_szZoneGroupName[zGroup], g_szStyleRecordPrint[style], g_szFinalTime[client], szRecordDiff, g_szBonusTimeDifference[client], g_StyleMapRankBonus[style][zGroup][client], g_iStyleBonusCount[style][zGroup]);
	}
	else if (!g_bBonusSRVRecord[client] && !g_bBonusFirstRecord[client] && !g_bBonusPBRecord[client]) // Player did not beat bonus record nor set 1st bonus time nor beat bonus PB using style
	{
		CPrintToChat(client, "%t", "StyleBonusFinished5", g_szChatPrefix, szName, g_szZoneGroupName[zGroup], g_szStyleRecordPrint[style], g_szFinalTime[client], szRecordDiff, g_szBonusTimeDifference[client], g_StyleMapRankBonus[style][zGroup][client], g_iStyleBonusCount[style][zGroup]);
		PrintToConsole(client, "Surftimer | %s finished %s %s in %s [SR %s | PB %s | Rank #%i/%i]", szName, g_szZoneGroupName[zGroup], g_szStyleRecordPrint[style], g_szFinalTime[client], szRecordDiff, g_szBonusTimeDifference[client], g_StyleMapRankBonus[style][zGroup][client], g_iStyleBonusCount[style][zGroup]);
	}

	CheckBonusStyleRanks(client, zGroup, style);

	if (rank == 9999999 && IsValidClient(client))
		CPrintToChat(client, "%t", "FailedSaveData", g_szChatPrefix);

	CalculatePlayerRank(client, style);
	return;
}

public void CheckBonusStyleRanks(int client, int zGroup, int style)
{
	// if client has risen in rank,
	if (g_StyleOldMapRankBonus[style][zGroup][client] > g_StyleMapRankBonus[style][zGroup][client])
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsValidClient(i) && !IsFakeClient(i) && i != client)
			{ // if clients rank used to be bigger than i's, 2nd: clients new rank is at least as big as i's
				if (g_StyleOldMapRankBonus[style][zGroup][client] > g_StyleMapRankBonus[style][zGroup][i] && g_StyleMapRankBonus[style][zGroup][client] <= g_StyleMapRankBonus[style][zGroup][i])
					g_StyleMapRankBonus[style][zGroup][i]++;
			}
		}
	}
}

public void GetSpeedColour(int client, int speed, int type)
{
	int pos;
	if (g_fMaxVelocity == 10000.0)
	{
		if (type == 1 && g_SpeedMode[client] == 0) // green
		{
			pos = RoundToFloor(speed / 400.0);
			if (pos > 24)
				pos = 24;
			Format(g_szSpeedColour[client], sizeof(g_szSpeedColour), g_sz10000mvGradient[pos]);
		}
		else if (type == 2 && g_SpeedMode[client] == 0) // rainbow
		{
			pos = RoundToFloor(speed / 500.0);
			if (pos > 7)
				pos = 7;
			Format(g_szSpeedColour[client], sizeof(g_szSpeedColour), g_szRainbowGradient[pos]);
		}
		else if (type == 3 && g_SpeedMode[client] == 0) // gain/loss
		{
			if (speed >= GetConVarInt(g_hMaxVelocity))
				Format(g_szSpeedColour[client], sizeof(g_szSpeedColour), "#b8b");
			else if (g_iPreviousSpeed[client] < speed || g_iPreviousSpeed[client] == speed)
				Format(g_szSpeedColour[client], sizeof(g_szSpeedColour), "#8cd");
			else
				Format(g_szSpeedColour[client], sizeof(g_szSpeedColour), "#f32");

			g_iPreviousSpeed[client] = speed;
		}
		else
			Format(g_szSpeedColour[client], sizeof(g_szSpeedColour), "#eee");
	}
	else
	{
		if (type == 1 && g_SpeedMode[client] == 0) // green
		{
			pos = RoundToFloor(speed / 100.0);
			if (pos > 34)
				pos = 34;
			Format(g_szSpeedColour[client], sizeof(g_szSpeedColour), g_sz3500mvGradient[pos]);
		}
		else if (type == 2 && g_SpeedMode[client] == 0) // rainbow
		{
			pos = RoundToFloor(speed / 500.0);
			if (pos > 7)
				pos = 7;

			Format(g_szSpeedColour[client], sizeof(g_szSpeedColour), g_szRainbowGradient[pos]);
		}
		else if (type == 3 && g_SpeedMode[client] == 0) // gain/loss
		{
			if (speed >= GetConVarInt(g_hMaxVelocity))
				Format(g_szSpeedColour[client], sizeof(g_szSpeedColour), "#b8b");
			else if (g_iPreviousSpeed[client] < speed || g_iPreviousSpeed[client] == speed)
				Format(g_szSpeedColour[client], sizeof(g_szSpeedColour), "#8cd");
			else
				Format(g_szSpeedColour[client], sizeof(g_szSpeedColour), "#f32");

			g_iPreviousSpeed[client] = speed;
		}
		else
			Format(g_szSpeedColour[client], sizeof(g_szSpeedColour), "#eee");
	}
}

public void getColourName(int client, char[] buffer, int length, int colour)
{
	switch (colour)
	{
		case 0: Format(buffer, length, "White");
		case 1: Format(buffer, length, "Dark Red");
		case 2: Format(buffer, length, "Green");
		case 3: Format(buffer, length, "Limegreen");
		case 4: Format(buffer, length, "Blue");
		case 5: Format(buffer, length, "Lightgreen");
		case 6: Format(buffer, length, "Red");
		case 7: Format(buffer, length, "Grey");
		case 8: Format(buffer, length, "Yellow");
		case 9: Format(buffer, length, "Lightblue");
		case 10: Format(buffer, length, "Darkblue");
		case 11: Format(buffer, length, "Pink");
		case 12: Format(buffer, length, "Light Red");
		case 13: Format(buffer, length, "Purple");
		case 14: Format(buffer, length, "Dark Grey");
		case 15: Format(buffer, length, "Orange");
	}

	return;
}

public void diffForHumans(int unix, char[] buffer, int size, int type)
{
	int years, months, days, hours, mins, secs;
	if (type == 0)
	{
		if (unix > 31535999)
		{
			years = unix / 60 / 60 / 24 / 365;
			Format(buffer, size, "%d year%s ago", years, years==1?"":"s");
		}
		if (unix > 2591999)
		{
			months = unix / 60 / 60 / 24 / 30;
			Format(buffer, size, "%d month%s ago", months, months==1?"":"s");
		}
		if (unix > 86399)
		{
			days = unix / 60 / 60 / 24;
			hours = unix / 3600 % 60;
			mins = unix / 60 % 60;
			secs = unix % 60;
			Format(buffer, size, "%d day%s ago", days, days==1?"":"s");
		}
		else if (unix > 3599)
		{
			hours = unix / 3600 % 60;
			mins = unix / 60 % 60;
			secs = unix % 60;
			Format(buffer, size, "%d hour%s %d minute%s %d second%s ago", hours, hours==1?"":"s", mins, mins==1?"":"s", secs, secs==1?"":"s");
		}
		else if (unix > 59)
		{
			mins = unix / 60 % 60;
			secs = unix % 60;
			Format(buffer, size, "%d minute%s %d second%s ago", mins, mins==1?"":"s", secs, secs==1?"":"s");
		}
		else
		{
			secs = unix;
			Format(buffer, size, "%d second%s ago", secs, secs==1?"":"s");
		}
	}
	else if (type == 1)
	{
		if (unix > 31535999)
		{
			years = unix / 60 / 60 / 24 / 365;
			Format(buffer, size, "%d year%s ago", years, years==1?"":"s");
		}
		if (unix > 2591999)
		{
			months = unix / 60 / 60 / 24 / 30;
			Format(buffer, size, "%d month%s ago", months, months==1?"":"s");
		}
		if (unix > 86399)
		{
			days = unix / 60 / 60 / 24;
			Format(buffer, size, "%d day%s ago", days, days==1?"":"s");
		}
		else if (unix > 3599)
		{
			hours = unix / 3600 % 60;
			Format(buffer, size, "%d hour%s ago", hours, hours==1?"":"s");
		}
		else if (unix > 59)
		{
			mins = unix / 60 % 60;
			Format(buffer, size, "%d minute%s ago", mins, mins==1?"":"s");
		}
		else
		{
			secs = unix;
			if (secs < 1)
				secs = 1;
			Format(buffer, size, "%d second%s ago", secs, secs==1?"":"s");
		}
	}
}

public void totalTimeForHumans(int unix, char[] buffer, int size)
{
	int years, months, days, hours, mins, secs;
	if (unix > 31535999)
	{
		years = unix / 60 / 60 / 24 / 365;
		months = unix / 60 / 60 / 24 / 30;
		days = unix / 60 / 60 / 24;
		hours = unix / 3600 % 60;
		mins = unix / 60 % 60;
		secs = unix % 60;
		Format(buffer, size, "%d year%s %d month%s %d day%s %d hour%s %d minute%s %d second%s", years, years==1?"":"s", months, months==1?"":"s", days, days==1?"":"s", hours, hours==1?"":"s", mins, mins==1?"":"s", secs, secs==1?"":"s");
	}
	if (unix > 2591999)
	{
		months = unix / 60 / 60 / 24 / 30;
		days = unix / 60 / 60 / 24;
		hours = unix / 3600 % 60;
		mins = unix / 60 % 60;
		secs = unix % 60;
		Format(buffer, size, "%d month%s %d day%s %d hour%s %d minute%s %d second%s", months, months==1?"":"s", days, days==1?"":"s", hours, hours==1?"":"s", mins, mins==1?"":"s", secs, secs==1?"":"s");
	}
	if (unix > 86399)
	{
		days = unix / 60 / 60 / 24;
		hours = unix / 3600 % 60;
		mins = unix / 60 % 60;
		secs = unix % 60;
		Format(buffer, size, "%d day%s %d hour%s %d minute%s %d second%s", days, days==1?"":"s", hours, hours==1?"":"s", mins, mins==1?"":"s", secs, secs==1?"":"s");
	}
	else if (unix > 3599)
	{
		hours = unix / 3600 % 60;
		mins = unix / 60 % 60;
		secs = unix % 60;
		Format(buffer, size, "%d hour%s %d minute%s %d second%s", hours, hours==1?"":"s", mins, mins==1?"":"s", secs, secs==1?"":"s");
	}
	else if (unix > 59)
	{
		mins = unix / 60 % 60;
		secs = unix % 60;
		Format(buffer, size, "%d minute%s %d second%s", mins, mins==1?"":"s", secs, secs==1?"":"s");
	}
	else
	{
		secs = unix;
		Format(buffer, size, "%d second%s", secs, secs==1?"":"s");
	}
}

public void sendDiscordAnnouncement(char szName[128], char szMapName[128], char szTime[32], char szRecordDiff[32])
{
	//Test which style to use
	if (!GetConVarBool(g_dcKSFStyle))
	{
		//Get the WebHook
		char webhook[1024], webhookName[1024];
		GetConVarString(g_hRecordAnnounceDiscord, webhook, sizeof(webhook));
		GetConVarString(g_dcMapRecordName, webhookName, sizeof(webhookName));
		if (StrEqual(webhook, ""))
			return;

		char szMention[128], szTitle[256], szColor[128], szTimeDiscord[128], szUrlMain[1024], szUrlThumb[1024];
		GetConVarString(g_dcTitle, szTitle, sizeof(szTitle));
		GetConVarString(g_dcMention, szMention, sizeof(szMention));
		GetConVarString(g_dcColor, szColor, sizeof(szColor));
		GetConVarString(g_dcUrl_main, szUrlMain, sizeof(szUrlMain));
		GetConVarString(g_dcUrl_thumb, szUrlThumb, sizeof(szUrlThumb));
		ReplaceString(szTitle, sizeof(szTitle), "{Server_Name}", g_sServerName);
		Format(szTimeDiscord, sizeof(szTimeDiscord), "%s (%s)", szTime, szRecordDiff);

		SurfTimer_SendAnnouncement(webhook, webhookName, szMention, szColor, szTitle, szName, szTimeDiscord, szMapName, szUrlMain, szUrlThumb);
	}
	else
	{
		char webhook[1024], webhookName[1024];
		GetConVarString(g_hRecordAnnounceDiscord, webhook, sizeof(webhook));
		GetConVarString(g_dcMapRecordName, webhookName, sizeof(webhookName));
		if (StrEqual(webhook, ""))
			return;
		
		// Format The Message
		char szMessage[256];
		Format(szMessage, sizeof(szMessage), "```md\n# New Server Record on %s #\n\n[%s] beat the server record on < %s > with a time of < %s (%s) > ]:```", g_sServerName, szName, szMapName, szTime, szRecordDiff);

		SurfTimer_SendAnnouncementMessage(webhook, webhookName, szMessage);
	}
}

public void sendDiscordAnnouncementBonus(char szName[128], char szMapName[128], char szTime[32], int zGroup, char szRecordDiff[54])
{
	//Test which style to use
	if (!GetConVarBool(g_dcKSFStyle))
	{
		//Get the WebHook
		char webhook[1024], webhookN[1024], webhookName[1024];
		GetConVarString(g_hRecordAnnounceDiscord, webhookN, sizeof(webhookN));
		GetConVarString(g_hRecordAnnounceDiscordBonus, webhook, sizeof(webhook));
		GetConVarString(g_dcBonusRecordName, webhookName, sizeof(webhookName));
		if (StrEqual(webhook, ""))
			if (StrEqual(webhookN, ""))
				return;
			else
				webhook = webhookN;
		
		//Format the message
		char szTitle[256], szMention[128], szColor[128], szTimeDiscord[128], szGroup[8], szUrlMain[1024], szUrlThumb[1024];
		GetConVarString(g_dcUrl_main, szUrlMain, sizeof(szUrlMain));
		GetConVarString(g_dcUrl_thumb, szUrlThumb, sizeof(szUrlThumb));
		GetConVarString(g_dcTitleBonus, szTitle, sizeof(szTitle));
		GetConVarString(g_dcMention, szMention, sizeof(szMention));
		GetConVarString(g_dcColor, szColor, sizeof(szColor));
		ReplaceString(szTitle, sizeof(szTitle), "{Server_Name}", g_sServerName);
		Format(szTimeDiscord, sizeof(szTimeDiscord), "%s (%s)", szTime, szRecordDiff);
		IntToString(zGroup, szGroup, sizeof(szGroup));

		SurfTimer_SendAnnouncementBonus(webhook, webhookName, szMention, szColor, szTitle, szName, szTimeDiscord, szMapName, szGroup, szUrlMain, szUrlThumb);
	}
	else
	{
		char webhook[1024], webhookN[1024], webhookName[1024];
		GetConVarString(g_hRecordAnnounceDiscord, webhookN, sizeof(webhookN));
		GetConVarString(g_hRecordAnnounceDiscordBonus, webhook, sizeof(webhook));
		GetConVarString(g_dcBonusRecordName, webhookName, sizeof(webhookName));
		if (StrEqual(webhook, ""))
			if (StrEqual(webhookN, ""))
				return;
			else
				webhook = webhookN;

		// Format The Message
		char szMessage[256];
		Format(szMessage, sizeof(szMessage), "```md\n# New Bonus Server Record on %s #\n\n[%s] beat the bonus %i server record on < %s > with a time of < %s (%s) > ]:```", g_sServerName, szName, zGroup, szMapName, szTime, szRecordDiff);

		SurfTimer_SendAnnouncementMessageBonus(webhook, webhookName, szMessage);
	}
}

bool IsPlayerVip(int client, bool admin = true, bool reply = false)
{
	if (admin)
	{
		if (CheckCommandAccess(client, "", ADMFLAG_ROOT))
			return true;
	}

	if (!g_bVip[client] && !g_iHasEnforcedTitle[client])
	{
		if (reply)
		{
			CPrintToChat(client, "%t", "Misc43", g_szChatPrefix);
			PrintToConsole(client, "SurfTimer | This is a VIP feature");
		}
		return false;
	}

	return true;
}

public float GetStrafeSync(int client, bool sync)
{
	// Strafe sync taken from shavit's bhop timer
	return view_as<float>((sync)? (g_iGoodGains[client] == 0)? 100.0:(g_iGoodGains[client] / float(g_iTotalMeasures[client]) * 100.0):-1.0);
}

public void ResetSaveLocs()
{
	g_iSaveLocCount = 0;
	for (int i = 0; i < MAX_LOCS; i++)
	{
		for (int j = 0; j < 3; j++)
		{
			g_fSaveLocCoords[i][j] = 0.0;
			g_fSaveLocAngle[i][j] = 0.0;
			g_fSaveLocVel[i][j] = 0.0;
		}
		g_iSaveLocUnix[i] = 0;
		g_szSaveLocTargetname[i][0] = '\0';
	}
}

public void TeleportToSaveloc(int client, int id)
{
	g_iLastSaveLocIdClient[client] = id;
	ResetGravity(client);
	g_bPracticeMode[client] = true;
	g_bWrcpTimeractivated[client] = false;
	CL_OnStartTimerPress(client);
	DispatchKeyValue(client, "targetname", g_szSaveLocTargetname[id]);
	SetEntPropVector(client, Prop_Data, "m_vecVelocity", view_as<float>( { 0.0, 0.0, 0.0 } ));
	TeleportEntity(client, g_fSaveLocCoords[id], g_fSaveLocAngle[id], g_fSaveLocVel[id]);
	CreateTimer(0.1, noPrac, GetClientUserId(client));
}

public Action noPrac(Handle timer, int userid)//saveloc on start > startpos
{
	int client = GetClientOfUserId(userid);

	if (IsValidClient(client))
	{
		if (g_iClientInZone[client][0] == 1 || g_iClientInZone[client][0] == 5)
		{
			g_bPracticeMode[client] = false;
			if (g_bPause[client] == true)
				PauseMethod(client);
			//make sure timer enabled so run doesnt start in prac mode
			if (!g_bTimerEnabled[client])
				g_bTimerEnabled[client] = true;
			g_bTimerRunning[client] = false;
			g_bClientRestarting[client] = false;
			g_bWrcpTimeractivated[client] = false;
			g_bInStageZone[client] = false;
			g_bInStartZone[client] = true;
			g_bLeftZone[client] = false;
			g_bInBhop[client] = false;

			// Reset Run Variables
			tmpDiff[client] = 9999.0;
			g_fPauseTime[client] = 0.0;
			g_fStartPauseTime[client] = 0.0;
			g_bPause[client] = false;
			SetEntityMoveType(client, MOVETYPE_WALK);
			SetEntityRenderMode(client, RENDER_NORMAL);
			g_fCurrentRunTime[client] = 0.0;
			g_bPositionRestored[client] = false;
			g_bMissedMapBest[client] = true;
			g_bMissedBonusBest[client] = true;
			g_bTimerRunning[client] = true;
			g_bTop10Time[client] = false;
			// Strafe Sync
			g_iGoodGains[client] = 0;
			g_iTotalMeasures[client] = 0;
			g_iCurrentCheckpoint[client] = 0;
			g_iCheckpointsPassed[client] = 0;
			g_bIsValidRun[client] = false;
			Client_Stop(client, 0);
		}
	}
}

public void SendBugReport(int client)
{
	char webhook[1024];
	GetConVarString(g_hReportBugsDiscord, webhook, sizeof(webhook));
	if (StrEqual(webhook, ""))
		return;

	char dcBugTrackerName[64], sTitle[256];
	GetConVarString(g_dcBugTrackerName, dcBugTrackerName, sizeof(dcBugTrackerName));
	Format(sTitle, sizeof(sTitle), "Bug Type: %s ║ Server: %s ║ Map: %s", g_sBugType[client], g_sServerName, g_szMapName);

	SurfTimer_SendBugReport(client, webhook, dcBugTrackerName, sTitle, g_sBugMsg[client]);

	CPrintToChat(client, "%t", "Misc44", g_szChatPrefix);
}

public void CallAdmin(int client, char[] sText)
{
	char webhook[1024];
	GetConVarString(g_hCalladminDiscord, webhook, sizeof(webhook));
	if (StrEqual(webhook, ""))
		return;
	
	char dcCalladminName[64], sTitle[256];
	Format(sTitle, sizeof(sTitle), "Server: %s ║ Map: %s", g_sServerName, g_szMapName);
	GetConVarString(g_dcCalladminName, dcCalladminName, sizeof(dcCalladminName));

	SurfTimer_SendCallAdmin(client, webhook, dcCalladminName, sTitle, sText);

	CPrintToChat(client, "%t", "Misc45", g_szChatPrefix);
}

public void ReadDefaultTitlesWhitelist()
{
	ClearArray(g_DefaultTitlesWhitelist);
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "%s", DEFAULT_TITLES_WHITELIST_PATH);
	File whitelist = OpenFile(sPath, "r");
	if (whitelist != null)
	{
		char line[32];
		while (!IsEndOfFile(whitelist) && ReadFileLine(whitelist, line, sizeof(line)))
		{
			TrimString(line);
			if (StrContains(line, "//", true) == -1)
				PushArrayString(g_DefaultTitlesWhitelist, line);
		}
		delete whitelist;
	}
	else
		LogError("[SurfTimer] %s not found", DEFAULT_TITLES_WHITELIST_PATH);
}

public void LoadDefaultTitle(int client)
{
	// Set Defaults
	g_bEnforceTitle[client] = false;
	Format(g_szEnforcedTitle[client], sizeof(g_szEnforcedTitle), "");
	if (g_DefaultTitlesWhitelist != null)
		if ((FindStringInArray(g_DefaultTitlesWhitelist, g_szSteamID[client])) != -1)
			return;

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "%s", DEFAULT_TITLES_PATH);

	if (FileExists(sPath))
	{
		Handle kv = CreateKeyValues("Default Titles");
		if (FileToKeyValues(kv, sPath) && KvGotoFirstSubKey(kv))
		{
			char szBuffer[256];
			do
			{
				KvGetString(kv, "steamid", szBuffer, sizeof(szBuffer), "none");
				// Check if this keyvalue has a steamid
				if (!StrEqual(szBuffer, "none"))
				{
					// Does the steamid match the clients?
					if (StrEqual(g_szSteamID[client], szBuffer))
					{
						KvGetString(kv, "title", szBuffer, sizeof(szBuffer));
						SetDefaultTitle(client, szBuffer);
						g_iHasEnforcedTitle[client] = true;

						g_iEnforceTitleType[client] = 2;
						KvGetString(kv, "type", szBuffer, sizeof(szBuffer), "both");
						if (StrEqual(szBuffer, "scoreboard"))
							g_iEnforceTitleType[client] = 1;
						else if (StrEqual(szBuffer, "chat"))
							g_iEnforceTitleType[client] = 0;
						else
							g_iEnforceTitleType[client] = 2;

						break;
					} else {
						g_iHasEnforcedTitle[client] = false;
						continue;
					}

				}

				KvGetString(kv, "flag", szBuffer, sizeof(szBuffer), "none");
				// Has to be a flag since no steamid was found, otherwise invalid entry
				if (StrEqual(szBuffer, "none"))
					continue;

				// Check if client has access to this flag
				int bit = ReadFlagString(szBuffer);
				if (!CheckCommandAccess(client, "", bit))
					continue;

				// "type"
				g_iEnforceTitleType[client] = 2;
				KvGetString(kv, "type", szBuffer, sizeof(szBuffer), "both");
				if (StrEqual(szBuffer, "scoreboard"))
					g_iEnforceTitleType[client] = 1;
				else if (StrEqual(szBuffer, "chat"))
					g_iEnforceTitleType[client] = 0;
				else
					g_iEnforceTitleType[client] = 2;

				KvGetString(kv, "title", szBuffer, sizeof(szBuffer));
				SetDefaultTitle(client, szBuffer);
				break;

			} while (KvGotoNextKey(kv));
		}
		delete kv;
	}
	else
		LogError("[SurfTimer] %s not found", DEFAULT_TITLES_PATH);
}

public void SetDefaultTitle(int client, const char szTitle[256])
{
	// Set the clients default title
	g_bEnforceTitle[client] = true;
	Format(g_szEnforcedTitle[client], sizeof(g_szEnforcedTitle), szTitle);
	CreateTimer(1.0, SetClanTag, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public int GetStyleIndex(char[] szBuffer)
{
	for (int i = 0; i < sizeof(g_szStyleAcronyms); i++)
		if (StrEqual(szBuffer, g_szStyleAcronyms[i]))
			return i;

	return -1;
}

public void FormatPercentage(float perc, char[] buffer, int size)
{
	if (perc < 10.0)
		Format(buffer, size, "%.1f", perc);
	else if (perc == 100.0)
		Format(buffer, size, "100.0");
	else if (perc > 100.0)
		Format(buffer, size, "100.0");
	else
		Format(buffer, size, "%.1f", perc);
}

public bool IsPlayerZoner(int client)
{
	if (IsValidClient(client) && !IsFakeClient(client))
	{
		if ((GetUserFlagBits(client) & g_ZonerFlag) || (GetUserFlagBits(client) & ADMFLAG_ROOT) || g_bZoner[client])
			return true;
	}
	return false;
}

public bool IsPlayerTimerAdmin(int client)
{
	if (IsValidClient(client) && !IsFakeClient(client))
	{
		if ((GetUserFlagBits(client) & g_AdminMenuFlag) || (GetUserFlagBits(client) & ADMFLAG_ROOT))
			return true;
	}
	return false;
}

void PrintCSGOHUDText(int client, const char[] format, any ...)
{
	char buff[MAX_HINT_SIZE];
	VFormat(buff, sizeof(buff), format, 3);
	Format(buff, sizeof(buff), "</font>%s", buff);

	for(int i = strlen(buff); i < sizeof(buff) - 1; i++)
		buff[i] = '\n';

	buff[sizeof(buff) - 1] = '\0';

	Protobuf pb = view_as<Protobuf>(StartMessageOne("TextMsg", client, USERMSG_RELIABLE | USERMSG_BLOCKHOOKS));
	pb.SetInt("msg_dst", 4);
	pb.AddString("params", "#SFUI_ContractKillStart");
	pb.AddString("params", buff);
	pb.AddString("params", NULL_STRING);
	pb.AddString("params", NULL_STRING);
	pb.AddString("params", NULL_STRING);
	pb.AddString("params", NULL_STRING);

	EndMessage();
}

// Copied this stock from colorvariables with some modifications (new syntax, replaced stuff with g_hColor )
bool CGetColor(const char[] sName, char[] sColor, int iColorSize)
{
	if (sName[0] == '\0')
		return false;

	if (sName[0] == '@') {
		int iSpace;
		char sData[64];
		char m_sName[64];
		strcopy(m_sName, sizeof(m_sName), sName[1]);

		if ((iSpace = FindCharInString(m_sName, ' ')) != -1 && (iSpace + 1 < strlen(m_sName))) {
			strcopy(m_sName, iSpace + 1, m_sName);
			strcopy(sData, sizeof(sData), m_sName[iSpace + 1]);
		}

		if (sColor[0] != '\0') {
			return true;
		}

	} else if (sName[0] == '#') {
		if (strlen(sName) == 7) {
			Format(sColor, iColorSize, "\x07%s", sName[1]);
			return true;
		}
		if (strlen(sName) == 9) {
			Format(sColor, iColorSize, "\x08%s", sName[1]);
			return true;
		}
	} else if (StrContains(sName, "player ", false) == 0 && strlen(sName) > 7) {
		int iClient = StringToInt(sName[7]);

		if (iClient < 1 || iClient > MaxClients || !IsClientInGame(iClient)) {
			strcopy(sColor, iColorSize, "\x01");
			LogError("Invalid client index %d", iClient);
			return false;
		}

		strcopy(sColor, iColorSize, "\x01");
		switch (GetClientTeam(iClient)) {
			case 1: {
				Format(sColor, iColorSize, "team 0");
			}
			case 2: {
				Format(sColor, iColorSize, "team 1");
			}
			case 3: {
				Format(sColor, iColorSize, "team 2");
			}
		}
		return true;
	} else {
		Format(sColor, iColorSize, sName);
		return true;
	}

	return false;
}

bool IsValidDatabase(Database db, const char[] error)
{
    if (db == null || strlen(error))
    {
        return false;
    }

    return true;
}
