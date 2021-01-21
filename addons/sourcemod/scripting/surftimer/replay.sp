
// Botmimic3 - modified by 1NutWunDeR
// http://forums.alliedmods.net/showthread.php?t=164148

void setReplayTime(int zGrp, int stage, int style)
{
	char sPath[256], sTime[54], sBuffer[4][54];
	if (zGrp > 0)
	{
		if (style == 0)
			BuildPath(Path_SM, sPath, sizeof(sPath), "%s%s_bonus_%d.rec", CK_REPLAY_PATH, g_szMapName, zGrp);
		else
			BuildPath(Path_SM, sPath, sizeof(sPath), "%s%s_bonus_%d_style_%d.rec", CK_REPLAY_PATH, g_szMapName, zGrp, style);
	}
	else if (stage > 0)
		BuildPath(Path_SM, sPath, sizeof(sPath), "%s%s_stage_%d.rec", CK_REPLAY_PATH, g_szMapName, stage);
	else
	{
		if (style == 0)
			BuildPath(Path_SM, sPath, sizeof(sPath), "%s%s.rec", CK_REPLAY_PATH, g_szMapName);
		else
			BuildPath(Path_SM, sPath, sizeof(sPath), "%s%s_style_%d.rec", CK_REPLAY_PATH, g_szMapName, style);
	}

	FileHeader header;
	LoadRecordFromFile(sPath, header, true);
	Format(sTime, sizeof(sTime), "%s", header.Time);

	ExplodeString(sTime, ":", sBuffer, 4, 54);
	float time = (StringToFloat(sBuffer[0]) * 60);
	time += StringToFloat(sBuffer[1]);
	time += (StringToFloat(sBuffer[2]) / 100);
	if (zGrp == 0 && stage == 0)
	{
		// Map
		if ((g_fRecordStyleMapTime[style] - 0.01) < time < (g_fRecordStyleMapTime[style]) + 0.01)
			time = g_fRecordStyleMapTime[style];
	}
	else if (stage > 0)
	{
		// Stage
		if ((g_fStyleStageRecord[0][stage] - 0.01) < time < (g_fStyleStageRecord[0][stage]) + 0.01)
			g_fStageReplayTimes[stage] = g_fStyleStageRecord[0][stage];
		else
			g_fStageReplayTimes[stage] = time;
		return;
	}
	else
	{
		// Bonus
		if ((g_fStyleBonusFastest[style][zGrp] - 0.01) < time < (g_fStyleBonusFastest[style][zGrp]) + 0.01)
			time = g_fStyleBonusFastest[style][zGrp];
	}

	g_fReplayTimes[zGrp][style] = time;
}

public Action RespawnBot(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if (!client)
		return Plugin_Stop;

	if (g_hBotMimicsRecord[client] != null && IsValidClient(client) && !IsPlayerAlive(client) && IsFakeClient(client) && GetClientTeam(client) >= CS_TEAM_T)
	{
		TeamChangeActual(client, 2);
		CS_RespawnPlayer(client);
	}

	return Plugin_Stop;
}

public void StartRecording(int client)
{
	if (!IsValidClient(client) || IsFakeClient(client))
		return;
	
	StopRecording(client);
	if (g_cEnableRequiredPlayersRecording.BoolValue && !g_bRequiredPlayersRecording) // return if limited recording is disabled
		return;

	g_hRecording[client] = CreateArray(sizeof(FrameInfo));
	g_hRecordingAdditionalTeleport[client] = CreateArray(sizeof(AdditionalTeleport));
	GetClientAbsOrigin(client, g_fInitialPosition[client]);
	GetClientEyeAngles(client, g_fInitialAngles[client]);
	g_RecordedTicks[client] = 0;
	g_OriginSnapshotInterval[client] = 0;
}

public void StopRecording(int client)
{
	delete g_hRecording[client];
	delete g_hRecordingAdditionalTeleport[client];
	g_hRecording[client] = null;
	g_hRecordingAdditionalTeleport[client] = null;

	g_RecordedTicks[client] = 0;
	g_RecordPreviousWeapon[client] = 0;
	g_CurrentAdditionalTeleportIndex[client] = 0;
	g_OriginSnapshotInterval[client] = 0;
}

public void SaveRecording(int client, int zgroup, int style)
{
	if (!IsValidClient(client) || g_hRecording[client] == null)
		return;
	else
	{
		g_bNewReplay[client] = false;
		g_bNewBonus[client] = false;
	}

	char sPath2[256];
	// Check if the default record folder exists
	BuildPath(Path_SM, sPath2, sizeof(sPath2), "%s", CK_REPLAY_PATH);
	if (!DirExists(sPath2))
		CreateDirectory(sPath2, 511);

	// Build path
	char sPath3[256];
	Format(sPath3, sizeof(sPath3), "%s%s", CK_REPLAY_PATH, g_szMapName);

	// Bonus replay path
	if (zgroup > 0)
		Format(sPath3, sizeof(sPath3), "%s_bonus_%d", sPath3, zgroup);
	
	// Style replay path
	if (style > 0)
		Format(sPath3, sizeof(sPath3), "%s_style_%d", sPath3, style);
	
	// Finish the path
	Format(sPath3, sizeof(sPath3), "%s.rec", sPath3);
	BuildPath(Path_SM, sPath2, sizeof(sPath2), sPath3);

	if (FileExists(sPath2) && GetConVarBool(g_hBackupReplays))
	{
		char newPath[256];
		Format(newPath, 256, "%s.bak", sPath2);
		RenameFile(newPath, sPath2);
	}

	char szName[MAX_NAME_LENGTH];
	GetClientName(client, szName, MAX_NAME_LENGTH);

	FileHeader header;
	header.BinaryFormatVersion = BINARY_FORMAT_VERSION;
	strcopy(header.Time, sizeof(FileHeader::Time), g_szFinalTime[client]);
	header.TickCount = GetArraySize(g_hRecording[client]);
	strcopy(header.Playername, sizeof(FileHeader::Playername), szName);
	header.Checkpoints = 0; // So that KZTimers replays work
	Array_Copy(g_fInitialPosition[client], header.InitialPosition, 3);
	Array_Copy(g_fInitialAngles[client], header.InitialAngles, 3);
	header.Frames = g_hRecording[client];

	if (GetArraySize(g_hRecordingAdditionalTeleport[client]) > 0)
		SetTrieValue(g_hLoadedRecordsAdditionalTeleport, sPath2, g_hRecordingAdditionalTeleport[client]);
	else
		delete g_hRecordingAdditionalTeleport[client];

	g_hRecordingAdditionalTeleport[client] = null;

	WriteRecordToDisk(sPath2, header);

	g_bNewReplay[client] = false;
	g_bNewBonus[client] = false;

	if (g_hRecording[client] != null)
		StopRecording(client);
}


public void LoadReplays()
{
	if (!GetConVarBool(g_hReplayBot) && !GetConVarBool(g_hBonusBot) && !GetConVarBool(g_hWrcpBot))
		return;

	// Init Variables:
	for (int i = 0; i < MAX_STYLES; i++)
		g_bMapReplay[i] = false;
	for (int i = 0; i < MAXZONEGROUPS; i++)
	{
		for (int j = 0; j < MAX_STYLES; j++)
		{
			g_fReplayTimes[i][j] = 0.0;
			g_bMapBonusReplay[i][j] = false;
		}
	}

	for (int i = 1; i <= g_TotalStages; i++)
	{
		g_bStageReplay[i] = false;
	}

	g_BonusBotCount = 0;
	g_RecordBot = -1;
	g_BonusBot = -1;
	g_WrcpBot = -1;
	g_iCurrentBonusReplayIndex = 0;

	Handle hSnapshot = CreateTrieSnapshot(g_hLoadedRecordsAdditionalTeleport);
	int iSnapshotLength = TrieSnapshotLength(hSnapshot);
	char sKey[PLATFORM_MAX_PATH];
	Handle hAT;
	for (int i = 0; i < iSnapshotLength; i++)
	{
		GetTrieSnapshotKey(hSnapshot, i, sKey, sizeof(sKey));
		GetTrieValue(g_hLoadedRecordsAdditionalTeleport, sKey, hAT);
		delete hAT;
	}
	delete hSnapshot;
	ClearTrie(g_hLoadedRecordsAdditionalTeleport);

	g_bFirstStageReplay = false;
	if (g_bhasStages)
	{
		char sPath2[256];
		for (int i = 1; i <= g_TotalStages; i++)
		{
			BuildPath(Path_SM, sPath2, sizeof(sPath2), "%s%s_stage_%d.rec", CK_REPLAY_PATH, g_szMapName, i);
			if (FileExists(sPath2))
			{
				if (!g_bFirstStageReplay)
				{
					g_StageReplayCurrentStage = i;
					g_bFirstStageReplay = true;
				}
				g_bStageReplay[i] = true;
				setReplayTime(0, i, 0);
			}
		}
		g_StageReplaysLoop = 1;
	}


	ClearTrie(g_hLoadedRecordsAdditionalTeleport);

	// Check that map replay exists
	char sPath[256];
	BuildPath(Path_SM, sPath, sizeof(sPath), "%s%s.rec", CK_REPLAY_PATH, g_szMapName);
	if (FileExists(sPath))
	{
		setReplayTime(0, 0, 0);
		g_bMapReplay[0] = true;
	}
	else// Check if backup exists
	{
		char sPathBack[256];
		BuildPath(Path_SM, sPathBack, sizeof(sPathBack), "%s%s.rec.bak", CK_REPLAY_PATH, g_szMapName);
		if (FileExists(sPathBack))
		{
			RenameFile(sPath, sPathBack);
			setReplayTime(0, 0, 0);
			g_bMapReplay[0] = true;
		}
	}

	// Try to fix old bonus replays
	BuildPath(Path_SM, sPath, sizeof(sPath), "%s%s_Bonus.rec", CK_REPLAY_PATH, g_szMapName);
	Handle hFilex = OpenFile(sPath, "r");

	if (hFilex != null)
	{
		FileHeader header;
		float initPos[3];
		char newPath[256];
		LoadRecordFromFile(sPath, header, true);
		Array_Copy(header.InitialPosition, initPos, 3);
		int zId = IsInsideZone(initPos, 50.0);
		if (zId != -1 && g_mapZones[zId].ZoneGroup != 0)
		{
			BuildPath(Path_SM, newPath, sizeof(newPath), "%s%s_bonus_%i.rec", CK_REPLAY_PATH, g_szMapName, g_mapZones[zId].ZoneGroup);
			if (RenameFile(newPath, sPath))
				PrintToServer("SurfTimer | Succesfully renamed bonus record file to: %s", newPath);
		}
		delete hFilex;
	}
	hFilex = null;
	delete hFilex;

	// Check if bonus replays exists
	for (int i = 1; i < g_mapZoneGroupCount; i++)
	{
		BuildPath(Path_SM, sPath, sizeof(sPath), "%s%s_bonus_%i.rec", CK_REPLAY_PATH, g_szMapName, i);
		if (FileExists(sPath))
		{
			setReplayTime(i, 0, 0);
			g_iBonusToReplay[g_BonusBotCount] = i;
			g_BonusBotCount++;
			g_bMapBonusReplay[i][0] = true;
		}
		else
		{
			// Check if backup exists
			char sPathBack[256];
			BuildPath(Path_SM, sPathBack, sizeof(sPathBack), "%s%s_bonus_%i.rec.bak", CK_REPLAY_PATH, g_szMapName, i);
			if (FileExists(sPathBack))
			{
				setReplayTime(i, 0, 0);
				RenameFile(sPath, sPathBack);
				g_iBonusToReplay[g_BonusBotCount] = i;
				g_BonusBotCount++;
				g_bMapBonusReplay[i][0] = true;
			}
		}
	}

	// Check if style map replays exist
	for (int i = 1; i < MAX_STYLES; i++)
	{
		BuildPath(Path_SM, sPath, sizeof(sPath), "%s%s_style_%d.rec", CK_REPLAY_PATH, g_szMapName, i);
		if (FileExists(sPath))
		{
			g_bMapReplay[i] = true;
			setReplayTime(0, 0, i);
		}
		else
		{
			// Check if backup exists
			char sPathBack[256];
			BuildPath(Path_SM, sPathBack, sizeof(sPathBack), "%s%s_style_%d.rec.bak", CK_REPLAY_PATH, g_szMapName, i);
			if (FileExists(sPathBack))
			{
				g_bMapReplay[i] = true;
				setReplayTime(0, 0, i);
				RenameFile(sPath, sPathBack);
			}
		}
	}

	// Check if style bonus replays exist
	for (int i = 1; i < MAXZONEGROUPS; i++)
	{
		for (int j = 1; j < MAX_STYLES; j++)
		{
			BuildPath(Path_SM, sPath, sizeof(sPath), "%s%s_bonus_%d_style_%d.rec", CK_REPLAY_PATH, g_szMapName, i, j);
			if (FileExists(sPath))
			{
				g_bMapBonusReplay[i][j] = true;
				setReplayTime(i, 0, j);
			}
			else
			{
				// Check if backup exists
				char sPathBack[256];
				BuildPath(Path_SM, sPathBack, sizeof(sPathBack), "%s%s_bonus_%d_style_%d.rec.bak", CK_REPLAY_PATH, g_szMapName, i, j);
				if (FileExists(sPathBack))
				{
					g_bMapBonusReplay[i][j] = true;
					setReplayTime(i, 0, j);
					RenameFile(sPath, sPathBack);
				}
			}
		}
	}

	if (g_bMapReplay[0])
		CreateTimer(1.0, RefreshBot, _, TIMER_FLAG_NO_MAPCHANGE);

	if (g_BonusBotCount > 0)
		CreateTimer(1.0, RefreshBonusBot, _, TIMER_FLAG_NO_MAPCHANGE);

	if (g_bhasStages)
		CreateTimer(1.0, RefreshWrcpBot, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void PlayRecord(int client, int type, int style)
{
	// He's currently recording. Don't start to play some record on him at the same time.
	if (!IsValidClient(client) || g_hRecording[client] != null || !IsFakeClient(client))
		return;

	char buffer[256];
	char sPath[256];

	int bonus;
	if (type > 0)
	{
		if (g_iCurrentBonusReplayIndex == 99)
			bonus = type;
		else
			bonus = g_iBonusToReplay[g_iCurrentBonusReplayIndex];
	}

	if (style == 0)
	{
		if (type == 0)
			Format(sPath, sizeof(sPath), "%s%s.rec", CK_REPLAY_PATH, g_szMapName);
		else if (type > 0)
			Format(sPath, sizeof(sPath), "%s%s_bonus_%d.rec", CK_REPLAY_PATH, g_szMapName, bonus);
		else if (type < 0)
			Format(sPath, sizeof(sPath), "%s%s_stage_%d.rec", CK_REPLAY_PATH, g_szMapName, (type * -1));
	}
	else
	{
		if (type == 0)
			Format(sPath, sizeof(sPath), "%s%s_style_%d.rec", CK_REPLAY_PATH, g_szMapName, style);
		else if (type > 0)
			Format(sPath, sizeof(sPath), "%s%s_bonus_%d_style_%d.rec", CK_REPLAY_PATH, g_szMapName, bonus, style);
		else if (type < 0)
			Format(sPath, sizeof(sPath), "%s%s_stage_%d_style_%d.rec", CK_REPLAY_PATH, g_szMapName, (type * -1), style);
	}

	FileHeader header;
	BuildPath(Path_SM, sPath, sizeof(sPath), "%s", sPath);
	LoadRecordFromFile(sPath, header, false);

	if (type == 0)
	{
		Format(g_szReplayTime, sizeof(g_szReplayTime), "%s", header.Time);
		Format(g_szReplayName, sizeof(g_szReplayName), "%s", header.Playername);
		if (style == 0)
		{
			Format(buffer, sizeof(buffer), "%s (%s)", g_szReplayName, g_szReplayTime);
			CS_SetClientClanTag(client, "MAP Replay");
			SetClientName(client, buffer);
		}
		else
		{
			// get style acronym and make it upper case
			char buffer2[128];
			Format(buffer2, sizeof(buffer2), g_szStyleAcronyms[style]);
			StringToUpper(buffer2);
			
			Format(buffer, sizeof(buffer), "%s: %s (%s)", buffer2, g_szReplayName, g_szReplayTime);
			SetClientName(client, buffer);

			Format(buffer, sizeof(buffer), "MAP Replay (%s)", buffer2);
			CS_SetClientClanTag(client, buffer);
		}
	}
	else if (type < 0)
	{
		int stage = type * -1;
		Format(g_szWrcpReplayTime[stage], sizeof(g_szWrcpReplayTime), "%s", header.Time);
		Format(g_szWrcpReplayName[stage], sizeof(g_szWrcpReplayName), "%s", header.Playername);
		Format(buffer, sizeof(buffer), "S%d %s (%s)", stage, g_szWrcpReplayName[stage], g_szWrcpReplayTime[stage]);
		g_iCurrentlyPlayingStage = stage;
		CS_SetClientClanTag(client, "STAGE Replay");
		SetClientName(client, buffer);
	}
	else
	{
		Format(g_szBonusTime, sizeof(g_szBonusTime), "%s", header.Time);
		Format(g_szBonusName, sizeof(g_szBonusName), "%s", header.Playername);
		if (style == 0)
		{
			Format(buffer, sizeof(buffer), "%s (%s)", g_szBonusName, g_szBonusTime);
			CS_SetClientClanTag(client, "BONUS Replay");
			SetClientName(client, buffer);
		}
		else
		{
			// get style acronym and make it upper case
			char buffer2[128];
			Format(buffer2, sizeof(buffer2), g_szStyleAcronyms[style]);
			StringToUpper(buffer2);
			
			Format(buffer, sizeof(buffer), "%s: %s (%s)", buffer2, g_szBonusName, g_szBonusTime);
			SetClientName(client, buffer);

			Format(buffer, sizeof(buffer), "SRB Replay (%s)", buffer2);
			CS_SetClientClanTag(client, buffer);
		}
	}

	g_hBotMimicsRecord[client] = header.Frames;
	g_BotMimicTick[client] = 0;
	g_BotMimicRecordTickCount[client] = header.TickCount;
	g_CurrentAdditionalTeleportIndex[client] = 0;

	Array_Copy(header.InitialPosition, g_fInitialPosition[client], 3);
	Array_Copy(header.InitialAngles, g_fInitialAngles[client], 3);

	// Disarm bot
	Client_RemoveAllWeapons(client);

	// Respawn him to get him moving!
	if (IsValidClient(client) && !IsPlayerAlive(client) && GetClientTeam(client) >= CS_TEAM_T)
	{
		CS_RespawnPlayer(client);
		if (GetConVarBool(g_hForceCT))
			TeamChangeActual(client, 2);
	}
}

public void WriteRecordToDisk(const char[] sPath, FileHeader header)
{
	Handle hFile = OpenFile(sPath, "wb");
	if (hFile == null)
	{
		LogError("Can't open the record file for writing! (%s)", sPath);
		return;
	}

	WriteFileCell(hFile, BM_MAGIC, 4);
	WriteFileCell(hFile, header.BinaryFormatVersion, 1);
	WriteFileCell(hFile, strlen(header.Time), 1);
	WriteFileString(hFile, header.Time, false);
	WriteFileCell(hFile, strlen(header.Playername), 1);
	WriteFileString(hFile, header.Playername, false);
	WriteFileCell(hFile, header.Checkpoints, 4);
	WriteFile(hFile, view_as<int>(header.InitialPosition), 3, 4);
	WriteFile(hFile, view_as<int>(header.InitialAngles), 2, 4);

	Handle hAdditionalTeleport;
	int iATIndex;
	GetTrieValue(g_hLoadedRecordsAdditionalTeleport, sPath, hAdditionalTeleport);

	int iTickCount = header.TickCount;
	WriteFileCell(hFile, iTickCount, 4);

	FrameInfo iFrame;
	for (int i = 0; i < iTickCount; i++)
	{
		GetArrayArray(header.Frames, i, iFrame, sizeof(FrameInfo));
		WriteFile(hFile, iFrame.PlayerButtons, sizeof(FrameInfo::PlayerButtons), 4);
		WriteFile(hFile, iFrame.PlayerImpulse, sizeof(FrameInfo::PlayerImpulse), 4);
		WriteFile(hFile, view_as<int>(iFrame.ActualVelocity), sizeof(FrameInfo::ActualVelocity), 4);
		WriteFile(hFile, view_as<int>(iFrame.PredictedVelocity), sizeof(FrameInfo::PredictedVelocity), 4);
		WriteFile(hFile, view_as<int>(iFrame.PredictedAngles), sizeof(FrameInfo::PredictedAngles), 4);
		WriteFile(hFile, view_as<int>(iFrame.NewWeapon), sizeof(FrameInfo::NewWeapon), 4);
		WriteFile(hFile, iFrame.PlayerSubtype, sizeof(FrameInfo::PlayerSubtype), 4);
		WriteFile(hFile, iFrame.PlayerSeed, sizeof(FrameInfo::PlayerSeed), 4);
		WriteFile(hFile, iFrame.AdditionalFields, sizeof(FrameInfo::AdditionalFields), 4);
		WriteFile(hFile, iFrame.Pause, sizeof(FrameInfo::Pause), 4);

		// Handle the optional Teleport call
		if (hAdditionalTeleport != null && iFrame.AdditionalFields & (ADDITIONAL_FIELD_TELEPORTED_ORIGIN | ADDITIONAL_FIELD_TELEPORTED_ANGLES | ADDITIONAL_FIELD_TELEPORTED_VELOCITY))
		{
			AdditionalTeleport iAT;
			GetArrayArray(hAdditionalTeleport, iATIndex, iAT, sizeof(AdditionalTeleport));
			if (iFrame.AdditionalFields & ADDITIONAL_FIELD_TELEPORTED_ORIGIN)
				WriteFile(hFile, view_as<int>(iAT.AtOrigin), 3, 4);
			if (iFrame.AdditionalFields & ADDITIONAL_FIELD_TELEPORTED_ANGLES)
				WriteFile(hFile, view_as<int>(iAT.AtAngles), 3, 4);
			if (iFrame.AdditionalFields & ADDITIONAL_FIELD_TELEPORTED_VELOCITY)
				WriteFile(hFile, view_as<int>(iAT.AtVelocity), 3, 4);
			iATIndex++;
		}
	}

	delete hFile;
	LoadReplays();
}

public void LoadRecordFromFile(const char[] path, FileHeader header, bool headerOnly)
{
	Handle hFile = OpenFile(path, "rb");
	if (hFile == null)
		return;
	int iMagic;
	ReadFileCell(hFile, iMagic, 4);
	if (iMagic != BM_MAGIC)
	{
		delete hFile;
		return;
	}
	int iBinaryFormatVersion;
	ReadFileCell(hFile, iBinaryFormatVersion, 1);
	header.BinaryFormatVersion = iBinaryFormatVersion;

	if (iBinaryFormatVersion > BINARY_FORMAT_VERSION)
	{
		delete hFile;
		return;
	}

	int iNameLength;
	ReadFileCell(hFile, iNameLength, 1);
	char szTime[MAX_NAME_LENGTH];
	ReadFileString(hFile, szTime, iNameLength + 1, iNameLength);
	szTime[iNameLength] = '\0';

	int iNameLength2;
	ReadFileCell(hFile, iNameLength2, 1);
	char szName[MAX_NAME_LENGTH];
	ReadFileString(hFile, szName, iNameLength2 + 1, iNameLength2);
	szName[iNameLength2] = '\0';

	int iCp;
	ReadFileCell(hFile, iCp, 4);

	ReadFile(hFile, view_as<int>(header.InitialPosition), 3, 4);
	ReadFile(hFile, view_as<int>(header.InitialAngles), 2, 4);

	int iTickCount;
	ReadFileCell(hFile, iTickCount, 4);

	strcopy(header.Time, sizeof(FileHeader::Time), szTime);
	strcopy(header.Playername, sizeof(FileHeader::Playername), szName);
	header.Checkpoints = iCp;
	header.TickCount = iTickCount;
	header.Frames = null;

	if (headerOnly)
	{
		delete hFile;
		return;
	}

	Handle hRecordFrames = CreateArray(sizeof(FrameInfo));
	Handle hAdditionalTeleport = CreateArray(sizeof(AdditionalTeleport));

	FrameInfo iFrame;
	for (int i = 0; i < iTickCount; i++)
	{
		ReadFile(hFile, iFrame.PlayerButtons, sizeof(FrameInfo::PlayerButtons), 4);
		ReadFile(hFile, iFrame.PlayerImpulse, sizeof(FrameInfo::PlayerImpulse), 4);
		ReadFile(hFile, view_as<int>(iFrame.ActualVelocity), sizeof(FrameInfo::ActualVelocity), 4);
		ReadFile(hFile, view_as<int>(iFrame.PredictedVelocity), sizeof(FrameInfo::PredictedVelocity), 4);
		ReadFile(hFile, view_as<int>(iFrame.PredictedAngles), sizeof(FrameInfo::PredictedAngles), 4);
		ReadFile(hFile, view_as<int>(iFrame.NewWeapon), sizeof(FrameInfo::NewWeapon), 4);
		ReadFile(hFile, iFrame.PlayerSubtype, sizeof(FrameInfo::PlayerSubtype), 4);
		ReadFile(hFile, iFrame.PlayerSeed, sizeof(FrameInfo::PlayerSeed), 4);
		ReadFile(hFile, iFrame.AdditionalFields, sizeof(FrameInfo::AdditionalFields), 4);
		ReadFile(hFile, iFrame.Pause, sizeof(FrameInfo::Pause), 4);
		PushArrayArray(hRecordFrames, iFrame, sizeof(FrameInfo));

		if (iFrame.AdditionalFields & (ADDITIONAL_FIELD_TELEPORTED_ORIGIN | ADDITIONAL_FIELD_TELEPORTED_ANGLES | ADDITIONAL_FIELD_TELEPORTED_VELOCITY))
		{
			AdditionalTeleport iAT;
			if (iFrame.AdditionalFields & ADDITIONAL_FIELD_TELEPORTED_ORIGIN)
				ReadFile(hFile, view_as<int>(iAT.AtOrigin), 3, 4);
			if (iFrame.AdditionalFields & ADDITIONAL_FIELD_TELEPORTED_ANGLES)
				ReadFile(hFile, view_as<int>(iAT.AtAngles), 3, 4);
			if (iFrame.AdditionalFields & ADDITIONAL_FIELD_TELEPORTED_VELOCITY)
				ReadFile(hFile, view_as<int>(iAT.AtVelocity), 3, 4);
			view_as<int>(iAT.AtFlags) = iFrame.AdditionalFields & (ADDITIONAL_FIELD_TELEPORTED_ORIGIN | ADDITIONAL_FIELD_TELEPORTED_ANGLES | ADDITIONAL_FIELD_TELEPORTED_VELOCITY);
			PushArrayArray(hAdditionalTeleport, iAT, sizeof(AdditionalTeleport));
		}
	}

	header.Frames = hRecordFrames;

	// Free any old handles if we already loaded this one once before.
	Handle hOldAT;
	if (GetTrieValue(g_hLoadedRecordsAdditionalTeleport, path, hOldAT))
	{
		delete hOldAT;
		RemoveFromTrie(g_hLoadedRecordsAdditionalTeleport, path);
	}

	if (GetArraySize(hAdditionalTeleport) > 0)
		SetTrieValue(g_hLoadedRecordsAdditionalTeleport, path, hAdditionalTeleport);
	else
		delete hAdditionalTeleport;

	delete hFile;

	return;
}

public Action RefreshBot(Handle timer)
{
	setBotQuota();
	LoadRecordReplay();
	return Plugin_Handled;
}

public void LoadRecordReplay()
{
	g_RecordBot = -1;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i) || !IsFakeClient(i) || IsClientSourceTV(i) || i == g_InfoBot || i == g_BonusBot || i == g_WrcpBot)
			continue;
		if (!IsPlayerAlive(i))
		{
			CS_RespawnPlayer(i);
			if (GetConVarBool(g_hForceCT))
				TeamChangeActual(i, 2);
		}

		g_RecordBot = i;
		g_fCurrentRunTime[g_RecordBot] = 0.0;
		break;
	}

	if (IsValidClient(g_RecordBot))
	{
		char clantag[100];
		CS_GetClientClanTag(g_RecordBot, clantag, sizeof(clantag));
		if (StrContains(clantag, "REPLAY") == -1)
			g_bNewRecordBot = true;

		g_iClientInZone[g_RecordBot][2] = 0;

		// "Having a bot in noclip and zero gravity ensures it's smooth" - Crashfort
		// https://github.com/crashfort/SourceToolAssist/blob/be9218583ee0a8086c817a5bd29101b2a260e5a7/Source/surf_segmentplay.sp#L113
		// Disabling noclip, makes the bot bug, look into later
		// SetEntityMoveType(g_RecordBot, MOVETYPE_NOCLIP);
		SetEntityGravity(g_RecordBot, 0.0);

		PlayRecord(g_RecordBot, 0, 0);
		// We can start multiple bots but first we need to get if bot has finished playing???
		SetEntityRenderColor(g_RecordBot, g_ReplayBotColor[0], g_ReplayBotColor[1], g_ReplayBotColor[2], 50);
		if (GetConVarBool(g_hPlayerSkinChange))
		{
			char szBuffer[256];
			GetConVarString(g_hReplayBotPlayerModel, szBuffer, 256);
			SetEntityModel(g_RecordBot, szBuffer);

			GetConVarString(g_hReplayBotArmModel, szBuffer, 256);
			SetEntPropString(g_RecordBot, Prop_Send, "m_szArmsModel", szBuffer);
		}
	}
	else
	{
		CreateTimer(1.0, RefreshBot, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}
public Action RefreshBonusBot(Handle timer)
{
	setBotQuota();
	LoadBonusReplay();
	return Plugin_Handled;
}

public void LoadBonusReplay()
{
	g_BonusBot = -1;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i) || !IsFakeClient(i) || IsClientSourceTV(i) || i == g_InfoBot || i == g_RecordBot || i == g_WrcpBot)
			continue;

		if (!IsPlayerAlive(i))
		{
			CS_RespawnPlayer(i);

			if (GetConVarBool(g_hForceCT))
				TeamChangeActual(i, 2);
		}

		g_BonusBot = i;
		g_fCurrentRunTime[g_BonusBot] = 0.0;
		break;
	}

	if (IsValidClient(g_BonusBot))
	{
		char clantag[100];
		CS_GetClientClanTag(g_BonusBot, clantag, sizeof(clantag));
		if (StrContains(clantag, "REPLAY") == -1)
			g_bNewBonusBot = true;
		g_iClientInZone[g_BonusBot][2] = g_iBonusToReplay[0];

		// "Having a bot in noclip and zero gravity ensures it's smooth" - Crashfort
		// https://github.com/crashfort/SourceToolAssist/blob/be9218583ee0a8086c817a5bd29101b2a260e5a7/Source/surf_segmentplay.sp#L113
		// Disabling noclip, makes the bot bug, look into later
		// SetEntityMoveType(g_BonusBot, MOVETYPE_NOCLIP);
		SetEntityGravity(g_BonusBot, 0.0);

		PlayRecord(g_BonusBot, 1, 0);
		SetEntityRenderColor(g_BonusBot, g_BonusBotColor[0], g_BonusBotColor[1], g_BonusBotColor[2], 50);
		if (GetConVarBool(g_hPlayerSkinChange))
		{
			char szBuffer[256];
			GetConVarString(g_hReplayBotPlayerModel, szBuffer, 256);
			SetEntityModel(g_BonusBot, szBuffer);

			GetConVarString(g_hReplayBotArmModel, szBuffer, 256);
			SetEntPropString(g_BonusBot, Prop_Send, "m_szArmsModel", szBuffer);
		}
	}
	else
	{
		// Make sure bot_quota is set correctly and try again
		CreateTimer(1.0, RefreshBonusBot, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action RefreshWrcpBot(Handle timer)
{
	setBotQuota();
	LoadWrcpReplay();
	return Plugin_Handled;
}

public void LoadWrcpReplay()
{
	g_WrcpBot = -1;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i) || !IsFakeClient(i) || IsClientSourceTV(i) || i == g_InfoBot || i == g_RecordBot || i == g_BonusBot)
			continue;

		if (!IsPlayerAlive(i))
		{
			CS_RespawnPlayer(i);

			if (GetConVarBool(g_hForceCT))
				TeamChangeActual(i, 2);
		}

		g_WrcpBot = i;
		g_fCurrentRunTime[g_WrcpBot] = 0.0;
		break;
	}

	if (IsValidClient(g_WrcpBot))
	{
		char clantag[100];
		CS_GetClientClanTag(g_WrcpBot, clantag, sizeof(clantag));

		g_iClientInZone[g_WrcpBot][2] = 0;

		// "Having a bot in noclip and zero gravity ensures it's smooth" - Crashfort
		// https://github.com/crashfort/SourceToolAssist/blob/be9218583ee0a8086c817a5bd29101b2a260e5a7/Source/surf_segmentplay.sp#L113
		// Disabling noclip, makes the bot bug, look into later
		// SetEntityMoveType(g_WrcpBot, MOVETYPE_NOCLIP);
		SetEntityGravity(g_WrcpBot, 0.0);

		PlayRecord(g_WrcpBot, -g_StageReplayCurrentStage, 0);
		SetEntityRenderColor(g_WrcpBot, 180, 142, 173, 50);
		if (GetConVarBool(g_hPlayerSkinChange))
		{
			char szBuffer[256];
			GetConVarString(g_hReplayBotPlayerModel, szBuffer, 256);
			SetEntityModel(g_WrcpBot, szBuffer);

			GetConVarString(g_hReplayBotArmModel, szBuffer, 256);
			SetEntPropString(g_WrcpBot, Prop_Send, "m_szArmsModel", szBuffer);
		}
	}
	else
	{
		// Make sure bot_quota is set correctly and try again
		CreateTimer(1.0, RefreshWrcpBot, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void StopPlayerMimic(int client)
{
	g_BotMimicTick[client] = 0;
	g_CurrentAdditionalTeleportIndex[client] = 0;
	g_BotMimicRecordTickCount[client] = 0;
	g_bValidTeleportCall[client] = false;
	delete g_hBotMimicsRecord[client];
}

public void RecordReplay (int client, int &buttons, int &subtype, int &seed, int &impulse, int &weapon, float angles[3], float vel[3])
{
	if (g_hRecording[client] != null && !IsFakeClient(client))
	{
		// Dont record pause frames
		if (g_bPause[client])
			return;

		FrameInfo iFrame;
		iFrame.PlayerButtons = buttons;
		iFrame.PlayerImpulse = impulse;

		float vVel[3];
		Entity_GetAbsVelocity(client, vVel);
		iFrame.ActualVelocity = vVel;
		iFrame.PredictedVelocity = vel;

		Array_Copy(angles, iFrame.PredictedAngles, 2);
		iFrame.NewWeapon = CSWeapon_NONE;
		iFrame.PlayerSubtype = subtype;
		iFrame.PlayerSeed = seed;

		// Save the current position
		if (g_OriginSnapshotInterval[client] > ORIGIN_SNAPSHOT_INTERVAL || g_createAdditionalTeleport[client])
		{
			AdditionalTeleport iAT;
			float fBuffer[3];
			GetClientAbsOrigin(client, fBuffer);
			Array_Copy(fBuffer, iAT.AtOrigin, 3);

			iAT.AtFlags = ADDITIONAL_FIELD_TELEPORTED_ORIGIN;
			PushArrayArray(g_hRecordingAdditionalTeleport[client], iAT, sizeof(AdditionalTeleport));
			g_OriginSnapshotInterval[client] = 0;
			g_createAdditionalTeleport[client] = false;
		}
		g_OriginSnapshotInterval[client]++;

		// Check for additional Teleports
		if (GetArraySize(g_hRecordingAdditionalTeleport[client]) > g_CurrentAdditionalTeleportIndex[client])
		{
			AdditionalTeleport iAT;
			GetArrayArray(g_hRecordingAdditionalTeleport[client], g_CurrentAdditionalTeleportIndex[client], iAT, sizeof(AdditionalTeleport));
			// Remember, we were teleported this frame!
			iFrame.AdditionalFields |= iAT.AtFlags;
			g_CurrentAdditionalTeleportIndex[client]++;
		}

		PushArrayArray(g_hRecording[client], iFrame, sizeof(FrameInfo));
		g_RecordedTicks[client]++;
	}
}

public void PlayReplay(int client, int &buttons, int &subtype, int &seed, int &impulse, int &weapon, float angles[3], float vel[3])
{
	if (client != g_RecordBot && client != g_BonusBot && client != g_WrcpBot)
	{
		// ServerCommand("sm_fixbot");
		return;
	}
	if (g_hBotMimicsRecord[client] != null)
	{
		if (!IsPlayerAlive(client) || GetClientTeam(client) < CS_TEAM_T || IsClientSourceTV(client))
			return;

		if (g_BotMimicTick[client] >= g_BotMimicRecordTickCount[client] || g_bReplayAtEnd[client])
		{
			if (client == g_BonusBot)
			{
				if (g_bManualBonusReplayPlayback)
				{
					if (g_iManualBonusReplayCount < 1)
						g_iManualBonusReplayCount++;
					else
					{
						g_iManualBonusReplayCount = 0;
						g_bManualBonusReplayPlayback = false;
						g_iCurrentBonusReplayIndex = 0;
						PlayRecord(g_BonusBot, 1, 0);
						g_iClientInZone[g_BonusBot][2] = g_iBonusToReplay[g_iCurrentBonusReplayIndex];

						StopPlayerMimic(g_BonusBot);
						CreateTimer(0.1, RefreshBonusBot, _, TIMER_FLAG_NO_MAPCHANGE);
						return;
					}
				}
				else
				{
					// Call to load another replay
					if (g_iCurrentBonusReplayIndex < (g_BonusBotCount-1))
						g_iCurrentBonusReplayIndex++;
					else
						g_iCurrentBonusReplayIndex = 0;

					g_iSelectedReplayType = 1;

					// g_bManualBonusReplayPlayback = true;
					g_iManualBonusReplayCount = 99;
					g_iSelectedBonusReplayStyle = 0;
					// g_iCurrentBonusReplayIndex = 99;
					g_iManualBonusToReplay = 1;
					PlayRecord(g_BonusBot, 1, 0);
					g_iClientInZone[g_BonusBot][2] = g_iBonusToReplay[g_iCurrentBonusReplayIndex];
				}
			}
			else if (client == g_RecordBot)
			{
				if (g_bManualReplayPlayback)
				{
					if (g_iManualReplayCount < 1)
						g_iManualReplayCount++;
					else
					{
						g_bManualReplayPlayback = false;
						g_iSelectedReplayType = 0;
						g_iManualReplayCount = 99;
						g_iSelectedReplayStyle = 0;
						PlayRecord(g_RecordBot, 0, 0);
						StopPlayerMimic(g_RecordBot);
						CreateTimer(0.1, RefreshBot, _, TIMER_FLAG_NO_MAPCHANGE);
						return;
					}
				}
			}
			else if (client == g_WrcpBot)
			{
				if (g_bManualStageReplayPlayback)
				{
					if (g_iManualStageReplayCount < 2)
						g_iManualStageReplayCount++;
					else
					{
						g_iManualStageReplayCount = 0;
						g_bManualStageReplayPlayback = false;
						g_StageReplaysLoop = 3;
						PlayRecord(g_WrcpBot, -g_StageReplayCurrentStage, 0);
					}
				}
				else
				{
					bool found = false;
					if (g_StageReplaysLoop == 3)
					{
						char sPath2[256];
						for (int i = 1; i <= g_TotalStages; i++)
						{
							if (i <= g_StageReplayCurrentStage)
								continue;

							BuildPath(Path_SM, sPath2, sizeof(sPath2), "%s%s_stage_%d.rec", CK_REPLAY_PATH, g_szMapName, i);

							if (FileExists(sPath2))
							{
								g_StageReplayCurrentStage = i;
								g_StageReplaysLoop = 0;
								found = true;
								break;
							}
						}

						if (!found)
						{
							for (int i = 1; i <= g_TotalStages; i++)
							{
								BuildPath(Path_SM, sPath2, sizeof(sPath2), "%s%s_stage_%d.rec", CK_REPLAY_PATH, g_szMapName, i);
								if (FileExists(sPath2))
								{
									g_StageReplayCurrentStage = i;
									g_StageReplaysLoop = 0;
									break;
								}
							}
						}
					}

					g_StageReplaysLoop++;
					g_iSelectedReplayType = 2;
					g_iManualStageReplayCount = 0;
					g_iSelectedReplayStage = g_StageReplayCurrentStage;
					PlayRecord(g_WrcpBot, -g_StageReplayCurrentStage, 0);
				}
			}

			if (!g_bReplayAtEnd[client])
			{
				g_fReplayRestarted[client] = GetEngineTime();
				SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 0.0);
				g_bReplayAtEnd[client] = true;
			}

			if (client != g_BonusBot)
			{
				g_BotMimicTick[client] = 0;
				g_CurrentAdditionalTeleportIndex[client] = 0;
			}

			SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.0);
			g_bReplayAtEnd[client] = false;
			g_BotMimicTick[client] = 0;
			g_CurrentAdditionalTeleportIndex[client] = 0;
		}

		FrameInfo iFrame;
		GetArrayArray(g_hBotMimicsRecord[client],
						g_BotMimicTick[client],
						iFrame,
						sizeof(FrameInfo)
					);

		buttons = iFrame.PlayerButtons;
		impulse = iFrame.PlayerImpulse;
		Array_Copy(iFrame.PredictedVelocity, vel, 3);
		Array_Copy(iFrame.PredictedAngles, angles, 2);
		subtype = iFrame.PlayerSubtype;
		seed = iFrame.PlayerSeed;
		weapon = 0;

		float fActualVelocity[3];
		Array_Copy(iFrame.ActualVelocity, fActualVelocity, 3);

		// We're supposed to teleport stuff?
		if (iFrame.AdditionalFields & (ADDITIONAL_FIELD_TELEPORTED_ORIGIN | ADDITIONAL_FIELD_TELEPORTED_ANGLES | ADDITIONAL_FIELD_TELEPORTED_VELOCITY))
		{
			AdditionalTeleport iAT;
			Handle hAdditionalTeleport;
			char sPath[PLATFORM_MAX_PATH];
			if (client == g_RecordBot)
			{
				if (g_iSelectedReplayType == 0 && g_iSelectedReplayStyle == 0)
					Format(sPath, sizeof(sPath), "%s%s.rec", CK_REPLAY_PATH, g_szMapName);
				else if (g_iSelectedReplayType == 0 && g_iSelectedReplayStyle > 0)
					Format(sPath, sizeof(sPath), "%s%s_style_%d.rec", CK_REPLAY_PATH, g_szMapName, g_iSelectedReplayStyle);
			}
			else if (client == g_BonusBot)
			{
				int bonus = g_iSelectedReplayBonus;
				if (g_iSelectedReplayType == 1 && g_iSelectedBonusReplayStyle == 0)
				{
					if (g_iCurrentBonusReplayIndex != 99)
						Format(sPath, sizeof(sPath), "%s%s_bonus_%d.rec", CK_REPLAY_PATH, g_szMapName, g_iBonusToReplay[g_iCurrentBonusReplayIndex]);
					else
						Format(sPath, sizeof(sPath), "%s%s_bonus_%d.rec", CK_REPLAY_PATH, g_szMapName, g_iManualBonusToReplay);
				}
				else if (g_iSelectedReplayType == 1 && g_iSelectedBonusReplayStyle > 0)
					Format(sPath, sizeof(sPath), "%s%s_bonus_%d_style_%d.rec", CK_REPLAY_PATH, g_szMapName, bonus, g_iSelectedBonusReplayStyle);
			}
			else if (client == g_WrcpBot)
			{
				int stage = g_iSelectedReplayStage;
				Format(sPath, sizeof(sPath), "%s%s_stage_%d.rec", CK_REPLAY_PATH, g_szMapName, stage);
			}

			BuildPath(Path_SM, sPath, sizeof(sPath), "%s", sPath);
			if (g_hLoadedRecordsAdditionalTeleport != null)
			{
				GetTrieValue(g_hLoadedRecordsAdditionalTeleport, sPath, hAdditionalTeleport);
				if (hAdditionalTeleport != null)
					GetArrayArray(hAdditionalTeleport, g_CurrentAdditionalTeleportIndex[client], iAT, 10);

				float fOrigin[3], fAngles[3], fVelocity[3];
				Array_Copy(iAT.AtOrigin, fOrigin, 3);
				Array_Copy(iAT.AtAngles, fAngles, 3);
				Array_Copy(iAT.AtVelocity, fVelocity, 3);

				// The next call to Teleport is ok.
				g_bValidTeleportCall[client] = true;

				if (iAT.AtFlags & ADDITIONAL_FIELD_TELEPORTED_ORIGIN)
				{
					if (iAT.AtFlags & ADDITIONAL_FIELD_TELEPORTED_ANGLES)
					{
						if (iAT.AtFlags & ADDITIONAL_FIELD_TELEPORTED_VELOCITY)
							TeleportEntity(client, fOrigin, fAngles, fVelocity);
						else
							TeleportEntity(client, fOrigin, fAngles, NULL_VECTOR);
					}
					else
					{
						if (iAT.AtFlags & ADDITIONAL_FIELD_TELEPORTED_VELOCITY)
							TeleportEntity(client, fOrigin, NULL_VECTOR, fVelocity);
						else
							TeleportEntity(client, fOrigin, NULL_VECTOR, NULL_VECTOR);
					}
				}
				else
				{
					if (iAT.AtFlags & ADDITIONAL_FIELD_TELEPORTED_ANGLES)
					{
						if (iAT.AtFlags & ADDITIONAL_FIELD_TELEPORTED_VELOCITY)
							TeleportEntity(client, NULL_VECTOR, fAngles, fVelocity);
						else
							TeleportEntity(client, NULL_VECTOR, fAngles, NULL_VECTOR);
					}
					else
					{
						if (iAT.AtFlags & ADDITIONAL_FIELD_TELEPORTED_VELOCITY)
							TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fVelocity);
					}
				}
				g_CurrentAdditionalTeleportIndex[client]++;
			}
		}

		// This is the first tick. Teleport him to the initial position
		if (g_BotMimicTick[client] == 0)
		{
			CL_OnStartTimerPress(client);
			g_bValidTeleportCall[client] = true;
			TeleportEntity(client, g_fInitialPosition[client], g_fInitialAngles[client], fActualVelocity);

		}
		else
		{
			g_bValidTeleportCall[client] = true;
			TeleportEntity(client, NULL_VECTOR, angles, fActualVelocity);
		}

		if (iFrame.NewWeapon != CSWeapon_NONE)
		{
			if (g_BotMimicTick[client] > 0)
				Client_RemoveAllWeapons(client);
			else
			{
				if ((client == g_RecordBot && g_bNewRecordBot) || (client == g_BonusBot && g_bNewBonusBot))
				{
					if (client == g_RecordBot)
						g_bNewRecordBot = false;
					else
						if (client == g_BonusBot)
							g_bNewBonusBot = false;
				}
				else
					Client_RemoveAllWeapons(client);
			}
		}
		g_BotMimicTick[client]++;
	}
}

public void Stage_StartRecording(int client)
{
	if (!IsValidClient(client) || IsFakeClient(client) || !g_bhasStages || g_bSavingWrcpReplay[client])
		return;

	if (g_cEnableRequiredPlayersRecording.BoolValue && !g_bRequiredPlayersRecording) // return if player recording is disabled
		return;

	GetClientAbsOrigin(client, g_fStageInitialPosition[client]);
	GetClientEyeAngles(client, g_fStageInitialAngles[client]);

	// Client is being recorded, save the ticks where the recording started
	if (g_hRecording[client] != null) 
	{
		g_StageRecStartFrame[client] = g_RecordedTicks[client];
		g_StageRecStartAT[client] = g_CurrentAdditionalTeleportIndex[client];
		return;
	}

	char szName[MAX_NAME_LENGTH];
	GetClientName(client, szName, MAX_NAME_LENGTH);

	if (g_hRecording[client] == null)
		StartRecording(client);

	g_StageRecStartFrame[client] = 0;
	g_StageRecStartAT[client] = 0;
}

public void Stage_SaveRecording(int client, int stage, char[] time)
{
	if (!IsValidClient(client) || g_hRecording[client] == null || g_bSavingWrcpReplay[client]) 
		return;

	char szName[MAX_NAME_LENGTH];
	GetClientName(client, szName, MAX_NAME_LENGTH);

	char sPath2[256];

	// Check if the default record folder exists?
	BuildPath(Path_SM, sPath2, sizeof(sPath2), "%s", CK_REPLAY_PATH);
	if (!DirExists(sPath2))
		CreateDirectory(sPath2, 511);

	BuildPath(Path_SM, sPath2, sizeof(sPath2), "%s%s_stage_%d.rec", CK_REPLAY_PATH, g_szMapName, stage);


	if (FileExists(sPath2) && GetConVarBool(g_hBackupReplays))
	{
		char newPath[256];
		Format(newPath, 256, "%s.bak", sPath2);
		RenameFile(newPath, sPath2);
	}

	// char szName[MAX_NAME_LENGTH];
	// GetClientName(client, szName, MAX_NAME_LENGTH);

	int startframe = g_StageRecStartFrame[client];
	int framesRecorded = GetArraySize(g_hRecording[client]) - startframe;

	FileHeader header;
	header.BinaryFormatVersion = BINARY_FORMAT_VERSION;
	strcopy(header.Time, sizeof(FileHeader::Time), time);
	header.TickCount = framesRecorded;
	strcopy(header.Playername, sizeof(FileHeader::Playername), szName);
	header.Checkpoints = 0; // So that KZTimers replays work
	Array_Copy(g_fStageInitialPosition[client], header.InitialPosition, 3);
	Array_Copy(g_fStageInitialAngles[client], header.InitialAngles, 3);

	Handle frames = CreateArray(sizeof(FrameInfo));

	for (int i = startframe; i < GetArraySize(g_hRecording[client]); i++)
	{
		FrameInfo iFrame;
		GetArrayArray(g_hRecording[client], i, iFrame, sizeof(FrameInfo));
		PushArrayArray(frames, iFrame, sizeof(FrameInfo));
	}

	header.Frames = frames;

	if (GetArraySize(g_hRecordingAdditionalTeleport[client]) > 0)
	{
		Handle additionalteleports = CreateArray(sizeof(AdditionalTeleport));

		for (int i = g_StageRecStartAT[client]; i < GetArraySize(g_hRecordingAdditionalTeleport[client]); i++)
		{
			AdditionalTeleport iAT;
			GetArrayArray(g_hRecordingAdditionalTeleport[client], i, iAT, sizeof(AdditionalTeleport));
			PushArrayArray(additionalteleports, iAT, sizeof(AdditionalTeleport));
		}

		SetTrieValue(g_hLoadedRecordsAdditionalTeleport, sPath2, additionalteleports);
	}

	WriteRecordToDisk(sPath2, header);
	g_StageRecStartFrame[client] = -1;
	if (g_bSavingWrcpReplay[client])
		g_bSavingWrcpReplay[client] = false;
}
