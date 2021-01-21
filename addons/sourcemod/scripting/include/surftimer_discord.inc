#if defined _surftimer_discord_included
 #endinput
#endif
#define _surftimer_discord_included

native void SurfTimer_SendBugReport(int client, char[] sWebhook, char[] sBotName, char[] sTitle, char[] sBugMessage);
native void SurfTimer_SendCallAdmin(int client, char[] sWebhook, char[] sBotName, char[] sTitle, char[] sTextMessage);
native void SurfTimer_SendAnnouncement(char[] sWebhook, char[] sBotName, char[] sMention, char[] sColor, char[] sTitle, char[] sName, char[] sTimeDiscord, char[] sMapName, char[] sUrlMain, char[] sUrlThumb);
native void SurfTimer_SendAnnouncementBonus(char[] sWebhook, char[] sBotName, char[] sMention, char[] sColor, char[] sTitle, char[] sName, char[] sTimeDiscord, char[] sMapName, char[] sGroup, char[] sUrlMain, char[] sUrlThumb);
native void SurfTimer_SendAnnouncementMessage(char[] sWebhook, char[] sBotName, char[] sMessage);
native void SurfTimer_SendAnnouncementMessageBonus(char[] sWebhook, char[] sBotName, char[] sMessage);

public SharedPlugin:__pl_surftimer_discord =
{
	name = "surftimer_discord",
	file = "surftimer_discord.smx",
	#if defined REQUIRE_PLUGIN
	required = 1,
	#else
	required = 0,
	#endif
};

public __pl_surftimer_discord_SetNTVOptional()
{
	MarkNativeAsOptional("SurfTimer_SendBugReport");
	MarkNativeAsOptional("SurfTimer_SendCallAdmin");
	MarkNativeAsOptional("SurfTimer_SendAnnouncement");
	MarkNativeAsOptional("SurfTimer_SendAnnouncementBonus");
	MarkNativeAsOptional("SurfTimer_SendAnnouncementMessage");
	MarkNativeAsOptional("SurfTimer_SendAnnouncementMessageBonus");
}
