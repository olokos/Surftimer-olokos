#pragma semicolon 1

#include <sourcemod>
#include <surftimer>

#undef REQUIRE_PLUGIN
#include <discord>

#pragma newdecls required

public Plugin myinfo =
{
	name = "SurfTimer - Discord",
	author = "All contributors",
	description = "a fork from fluffys cksurf fork",
	version = VERSION,
	url = "https://github.com/surftimer/Surftimer-olokos"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("SurfTimer_SendBugReport", Native_SendBugReport);
	CreateNative("SurfTimer_SendCallAdmin", Native_SendCallAdmin);
	CreateNative("SurfTimer_SendAnnouncement", Native_SendAnnouncement);
	CreateNative("SurfTimer_SendAnnouncementBonus", Native_SendAnnouncementBonus);
	CreateNative("SurfTimer_SendAnnouncementMessage", Native_SendAnnouncementMessage);
	CreateNative("SurfTimer_SendAnnouncementMessageBonus", Native_SendAnnouncementMessageBonus);


	RegPluginLibrary("surftimer_discord");
}

public int Native_SendBugReport(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	char sWebhook[1024], sBotName[64], sTitle[256], sBugMessage[256];

	GetNativeString(2, sWebhook, sizeof(sWebhook));
	GetNativeString(3, sBotName, sizeof(sBotName));
	GetNativeString(4, sTitle, sizeof(sTitle));
	GetNativeString(5, sBugMessage, sizeof(sBugMessage));

	// Send Discord Announcement
	DiscordWebHook hook = new DiscordWebHook(sWebhook);
	hook.SlackMode = true;

	hook.SetUsername(sBotName);

	MessageEmbed Embed = new MessageEmbed();
	Embed.SetTitle(sTitle);

	// Format Player
	char sName[MAX_NAME_LENGTH], sSteamID[32];
	GetClientName(client, sName, sizeof(sName));
	GetClientAuthId(client, AuthId_Steam2, sSteamID, sizeof(sSteamID));

	// Format Message
	char sMessage[512];
	Format(sMessage, sizeof(sMessage), "%s (%s): %s", sName, sSteamID, sBugMessage);
	Embed.AddField("", sMessage, true);

	hook.Embed(Embed);
	hook.Send();
	delete hook;
}

public int Native_SendCallAdmin(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	char sWebhook[1024], sBotName[64], sTitle[256], sTextMessage[256];
	GetNativeString(2, sWebhook, sizeof(sWebhook));
	GetNativeString(3, sBotName, sizeof(sBotName));
	GetNativeString(4, sTitle, sizeof(sTitle));
	GetNativeString(5, sTextMessage, sizeof(sTextMessage));

	// Send Discord Announcement
	DiscordWebHook hook = new DiscordWebHook(sWebhook);
	hook.SlackMode = true;

	hook.SetUsername(sBotName);

	MessageEmbed Embed = new MessageEmbed();
	Embed.SetTitle(sTitle);

	char sName[MAX_NAME_LENGTH], sSteamID[32];
	GetClientName(client, sName, sizeof(sName));
	GetClientAuthId(client, AuthId_Steam2, sSteamID, sizeof(sSteamID));

	// Format msg
	char sMessage[512];
	Format(sMessage, sizeof(sMessage), "%s (%s): @here %s", sName, sSteamID, sTextMessage);
	Embed.AddField("", sMessage, true);

	hook.Embed(Embed);
	hook.Send();
	delete hook;
}

public int Native_SendAnnouncement(Handle plugin, int numParams)
{
	char sWebhook[1024], sBotName[64], sMention[128], sTitle[256], sName[128], sColor[128], sTimeDiscord[128], sMapName[128], sGroup[8], sUrlMain[1024], sUrlThumb[1024];
	GetNativeString(1, sWebhook, sizeof(sWebhook));
	GetNativeString(2, sBotName, sizeof(sBotName));
	GetNativeString(3, sMention, sizeof(sMention));
	GetNativeString(4, sColor, sizeof(sColor));
	GetNativeString(5, sTitle, sizeof(sTitle));
	GetNativeString(6, sName, sizeof(sName));
	GetNativeString(7, sTimeDiscord, sizeof(sTimeDiscord));
	GetNativeString(8, sMapName, sizeof(sMapName));
	GetNativeString(9, sGroup, sizeof(sGroup));
	GetNativeString(10, sUrlMain, sizeof(sUrlMain));
	GetNativeString(11, sUrlThumb, sizeof(sUrlThumb));

	DiscordWebHook hook = new DiscordWebHook(sWebhook);
	hook.SlackMode = true;
	if (!StrEqual(sMention, "")) //Checks if mention is disabled
	{
		hook.SetContent(sMention);
	}
	hook.SetUsername(sBotName);
	MessageEmbed Embed = new MessageEmbed();
	Embed.SetColor(sColor);
	Embed.SetTitle(sTitle);
	Embed.AddField("Player", sName, true);
	Embed.AddField("Time", sTimeDiscord, true);
	Embed.AddField("Map", sMapName, true);

	if (!StrEqual(sUrlMain, ""))
	{
		StrCat(sUrlMain, sizeof(sUrlMain), sMapName);
		StrCat(sUrlMain, sizeof(sUrlMain), ".jpg");
		Embed.SetImage(sUrlMain);
	}


	if (!StrEqual(sUrlThumb, ""))
	{
		StrCat(sUrlThumb, sizeof(sUrlThumb), sMapName);
		StrCat(sUrlThumb, sizeof(sUrlThumb), ".jpg");
		Embed.SetThumb(sUrlThumb);
	}

	hook.Embed(Embed);

	hook.Send();
	delete hook;
}

public int Native_SendAnnouncementMessage(Handle plugin, int numParams)
{
	char sWebhook[1024], sBotName[64], sMessage[256];
	GetNativeString(1, sWebhook, sizeof(sWebhook));
	GetNativeString(2, sBotName, sizeof(sBotName));
	GetNativeString(3, sMessage, sizeof(sMessage));

	// Send Discord Announcement
	DiscordWebHook hook = new DiscordWebHook(sWebhook);
	hook.SlackMode = true;
	hook.SetUsername(sBotName);
	hook.SetContent(sMessage);
	hook.Send();
	delete hook;
}

public int Native_SendAnnouncementBonus(Handle plugin, int numParams)
{
	char sWebhook[1024], sBotName[64], sMention[128], sTitle[256], sName[128], sColor[128], sTimeDiscord[128], sMapName[128], sGroup[8], sUrlMain[1024], sUrlThumb[1024];
	GetNativeString(1, sWebhook, sizeof(sWebhook));
	GetNativeString(2, sBotName, sizeof(sBotName));
	GetNativeString(3, sMention, sizeof(sMention));
	GetNativeString(4, sColor, sizeof(sColor));
	GetNativeString(5, sTitle, sizeof(sTitle));
	GetNativeString(6, sName, sizeof(sName));
	GetNativeString(7, sTimeDiscord, sizeof(sTimeDiscord));
	GetNativeString(8, sMapName, sizeof(sMapName));
	GetNativeString(9, sGroup, sizeof(sGroup));
	GetNativeString(10, sUrlMain, sizeof(sUrlMain));
	GetNativeString(11, sUrlThumb, sizeof(sUrlThumb));

	DiscordWebHook hook = new DiscordWebHook(sWebhook);
	hook.SlackMode = true;
	
	if (!StrEqual(sMention, "")) //Checks if mention is disabled
	{
		hook.SetContent(sMention);
	}
	hook.SetUsername(sBotName);
	MessageEmbed Embed = new MessageEmbed();
	Embed.SetColor(sColor);
	Embed.SetTitle(sTitle);
	Embed.AddField("Player", sName, true);
	Embed.AddField("Time", sTimeDiscord, true);
	Embed.AddField("Map", sMapName, true);
	Embed.AddField("Bonus", sGroup, true);

	//Send the main image of the map
	if (!StrEqual(sUrlMain, ""))
	{
		StrCat(sUrlMain, sizeof(sUrlMain), sMapName);
		StrCat(sUrlMain, sizeof(sUrlMain), ".jpg");
		Embed.SetImage(sUrlMain);
	}

	//Send the thumb image of the map
	if (!StrEqual(sUrlThumb, ""))
	{
		StrCat(sUrlThumb, sizeof(sUrlThumb), sMapName);
		StrCat(sUrlThumb, sizeof(sUrlThumb), ".jpg");
		Embed.SetThumb(sUrlThumb);
	}

	//Send the message
	hook.Embed(Embed);

	hook.Send();
	delete hook;
}

public int Native_SendAnnouncementMessageBonus(Handle plugin, int numParams)
{
	char sWebhook[1024], sBotName[64], sMessage[256];
	GetNativeString(1, sWebhook, sizeof(sWebhook));
	GetNativeString(2, sBotName, sizeof(sBotName));
	GetNativeString(3, sMessage, sizeof(sMessage));

	// Send Discord Announcement
	DiscordWebHook hook = new DiscordWebHook(sWebhook);
	hook.SlackMode = true;
	hook.SetUsername(sBotName);
	hook.SetContent(sMessage);
	hook.Send();
	delete hook;
}
