ALTER TABLE `ck_announcements` DROP `steamid`;
ALTER TABLE `ck_playertimes` DROP `velStartXY`;
ALTER TABLE `ck_playertimes` DROP `velStartXYZ`;
ALTER TABLE `ck_playertimes` DROP `velStartZ`;
ALTER TABLE `ck_playertimes` DROP `velEndXY`;
ALTER TABLE `ck_playertimes` DROP `velEndXYZ`;
ALTER TABLE `ck_playertimes` DROP `velEndZ`;
ALTER TABLE `ck_bonus` DROP `velStartXY`;
ALTER TABLE `ck_bonus` DROP `velStartXYZ`;
ALTER TABLE `ck_bonus` DROP `velStartZ`;
ALTER TABLE `ck_bonus` DROP `velEndXY`;
ALTER TABLE `ck_bonus` DROP `velEndXYZ`;
ALTER TABLE `ck_bonus` DROP `velEndZ`;
ALTER TABLE `ck_wrcps` DROP `velStartXY`;
ALTER TABLE `ck_wrcps` DROP `velStartXYZ`;
ALTER TABLE `ck_wrcps` DROP `velStartZ`;
ALTER TABLE `ck_wrcps` DROP `velEndXY`;
ALTER TABLE `ck_wrcps` DROP `velEndXYZ`;
ALTER TABLE `ck_wrcps` DROP `velEndZ`;
ALTER TABLE `ck_playeroptions2` DROP `velcmphud`;
ALTER TABLE `ck_playeroptions2` DROP `velcmpchat`;

CREATE TABLE IF NOT EXISTS ck_checkpointsnew (
    steamid VARCHAR(32),
    mapname VARCHAR(32),
    cp1 FLOAT DEFAULT '0.0',
    cp2 FLOAT DEFAULT '0.0',
    cp3 FLOAT DEFAULT '0.0',
    cp4 FLOAT DEFAULT '0.0',
    cp5 FLOAT DEFAULT '0.0',
    cp6 FLOAT DEFAULT '0.0',
    cp7 FLOAT DEFAULT '0.0',
    cp8 FLOAT DEFAULT '0.0',
    cp9 FLOAT DEFAULT '0.0',
    cp10 FLOAT DEFAULT '0.0',
    cp11 FLOAT DEFAULT '0.0',
    cp12 FLOAT DEFAULT '0.0',
    cp13 FLOAT DEFAULT '0.0',
    cp14 FLOAT DEFAULT '0.0',
    cp15 FLOAT DEFAULT '0.0',
    cp16 FLOAT DEFAULT '0.0',
    cp17 FLOAT DEFAULT '0.0',
    cp18 FLOAT DEFAULT '0.0',
    cp19 FLOAT DEFAULT '0.0',
    cp20 FLOAT DEFAULT '0.0',
    cp21 FLOAT DEFAULT '0.0',
    cp22 FLOAT DEFAULT '0.0',
    cp23 FLOAT DEFAULT '0.0',
    cp24 FLOAT DEFAULT '0.0',
    cp25 FLOAT DEFAULT '0.0',
    cp26 FLOAT DEFAULT '0.0',
    cp27 FLOAT DEFAULT '0.0',
    cp28 FLOAT DEFAULT '0.0',
    cp29 FLOAT DEFAULT '0.0',
    cp30 FLOAT DEFAULT '0.0',
    cp31 FLOAT DEFAULT '0.0',
    cp32 FLOAT DEFAULT '0.0',
    cp33 FLOAT DEFAULT '0.0',
    cp34 FLOAT DEFAULT '0.0',
    cp35 FLOAT DEFAULT '0.0',
    zonegroup INT(12) NOT NULL DEFAULT 0,
    PRIMARY KEY (
        steamid,
        mapname,
        zonegroup
    )
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

REPLACE INTO ck_checkpointsnew (steamid, mapname, zonegroup)
SELECT * FROM (
    SELECT steamid, mapname, zonegroup FROM ck_checkpoints
    UNION ALL
    SELECT steamid, mapname, zonegroup FROM ck_checkpoints
    UNION ALL
    SELECT steamid, mapname, zonegroup FROM ck_checkpoints
) v;

UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp1 = (SELECT time FROM ck_checkpoints WHERE cp = 1 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp2 = (SELECT time FROM ck_checkpoints WHERE cp = 2 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp3 = (SELECT time FROM ck_checkpoints WHERE cp = 3 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp4 = (SELECT time FROM ck_checkpoints WHERE cp = 4 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp5 = (SELECT time FROM ck_checkpoints WHERE cp = 5 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp6 = (SELECT time FROM ck_checkpoints WHERE cp = 6 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp7 = (SELECT time FROM ck_checkpoints WHERE cp = 7 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp8 = (SELECT time FROM ck_checkpoints WHERE cp = 8 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp9 = (SELECT time FROM ck_checkpoints WHERE cp = 9 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp10 = (SELECT time FROM ck_checkpoints WHERE cp = 10 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp11 = (SELECT time FROM ck_checkpoints WHERE cp = 11 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp12 = (SELECT time FROM ck_checkpoints WHERE cp = 12 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp13 = (SELECT time FROM ck_checkpoints WHERE cp = 13 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp14 = (SELECT time FROM ck_checkpoints WHERE cp = 14 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp15 = (SELECT time FROM ck_checkpoints WHERE cp = 15 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp16 = (SELECT time FROM ck_checkpoints WHERE cp = 16 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp17 = (SELECT time FROM ck_checkpoints WHERE cp = 17 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp18 = (SELECT time FROM ck_checkpoints WHERE cp = 18 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp19 = (SELECT time FROM ck_checkpoints WHERE cp = 19 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp20 = (SELECT time FROM ck_checkpoints WHERE cp = 20 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp21 = (SELECT time FROM ck_checkpoints WHERE cp = 21 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp22 = (SELECT time FROM ck_checkpoints WHERE cp = 22 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp23 = (SELECT time FROM ck_checkpoints WHERE cp = 23 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp24 = (SELECT time FROM ck_checkpoints WHERE cp = 24 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp25 = (SELECT time FROM ck_checkpoints WHERE cp = 25 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp26 = (SELECT time FROM ck_checkpoints WHERE cp = 26 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp27 = (SELECT time FROM ck_checkpoints WHERE cp = 27 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp28 = (SELECT time FROM ck_checkpoints WHERE cp = 28 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp29 = (SELECT time FROM ck_checkpoints WHERE cp = 29 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp30 = (SELECT time FROM ck_checkpoints WHERE cp = 30 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp31 = (SELECT time FROM ck_checkpoints WHERE cp = 31 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp32 = (SELECT time FROM ck_checkpoints WHERE cp = 32 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp33 = (SELECT time FROM ck_checkpoints WHERE cp = 33 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp34 = (SELECT time FROM ck_checkpoints WHERE cp = 34 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);
UPDATE ck_checkpointsnew SET ck_checkpointsnew.cp35 = (SELECT time FROM ck_checkpoints WHERE cp = 35 AND time > 0 AND ck_checkpoints.steamid = ck_checkpointsnew.steamid AND ck_checkpoints.mapname = ck_checkpointsnew.mapname AND ck_checkpoints.zonegroup = ck_checkpointsnew.zonegroup);


UPDATE ck_checkpointsnew SET cp1 = 0 WHERE cp1 IS NULL;
UPDATE ck_checkpointsnew SET cp2 = 0 WHERE cp2 IS NULL;
UPDATE ck_checkpointsnew SET cp3 = 0 WHERE cp3 IS NULL;
UPDATE ck_checkpointsnew SET cp4 = 0 WHERE cp4 IS NULL;
UPDATE ck_checkpointsnew SET cp5 = 0 WHERE cp5 IS NULL;
UPDATE ck_checkpointsnew SET cp6 = 0 WHERE cp6 IS NULL;
UPDATE ck_checkpointsnew SET cp7 = 0 WHERE cp7 IS NULL;
UPDATE ck_checkpointsnew SET cp8 = 0 WHERE cp8 IS NULL;
UPDATE ck_checkpointsnew SET cp9 = 0 WHERE cp9 IS NULL;
UPDATE ck_checkpointsnew SET cp10 = 0 WHERE cp10 IS NULL;
UPDATE ck_checkpointsnew SET cp11 = 0 WHERE cp11 IS NULL;
UPDATE ck_checkpointsnew SET cp12 = 0 WHERE cp12 IS NULL;
UPDATE ck_checkpointsnew SET cp13 = 0 WHERE cp13 IS NULL;
UPDATE ck_checkpointsnew SET cp14 = 0 WHERE cp14 IS NULL;
UPDATE ck_checkpointsnew SET cp15 = 0 WHERE cp15 IS NULL;
UPDATE ck_checkpointsnew SET cp16 = 0 WHERE cp16 IS NULL;
UPDATE ck_checkpointsnew SET cp17 = 0 WHERE cp17 IS NULL;
UPDATE ck_checkpointsnew SET cp18 = 0 WHERE cp18 IS NULL;
UPDATE ck_checkpointsnew SET cp19 = 0 WHERE cp19 IS NULL;
UPDATE ck_checkpointsnew SET cp20 = 0 WHERE cp20 IS NULL;
UPDATE ck_checkpointsnew SET cp21 = 0 WHERE cp21 IS NULL;
UPDATE ck_checkpointsnew SET cp22 = 0 WHERE cp22 IS NULL;
UPDATE ck_checkpointsnew SET cp23 = 0 WHERE cp23 IS NULL;
UPDATE ck_checkpointsnew SET cp24 = 0 WHERE cp24 IS NULL;
UPDATE ck_checkpointsnew SET cp25 = 0 WHERE cp25 IS NULL;
UPDATE ck_checkpointsnew SET cp26 = 0 WHERE cp26 IS NULL;
UPDATE ck_checkpointsnew SET cp27 = 0 WHERE cp27 IS NULL;
UPDATE ck_checkpointsnew SET cp28 = 0 WHERE cp28 IS NULL;
UPDATE ck_checkpointsnew SET cp29 = 0 WHERE cp29 IS NULL;
UPDATE ck_checkpointsnew SET cp30 = 0 WHERE cp30 IS NULL;
UPDATE ck_checkpointsnew SET cp31 = 0 WHERE cp31 IS NULL;
UPDATE ck_checkpointsnew SET cp32 = 0 WHERE cp32 IS NULL;
UPDATE ck_checkpointsnew SET cp33 = 0 WHERE cp33 IS NULL;
UPDATE ck_checkpointsnew SET cp34 = 0 WHERE cp34 IS NULL;
UPDATE ck_checkpointsnew SET cp35 = 0 WHERE cp35 IS NULL;

ALTER TABLE ck_checkpoints RENAME TO ck_checkpointsold;
ALTER TABLE ck_checkpointsnew RENAME TO ck_checkpoints;
