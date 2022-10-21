#include <sourcemod>
#include <sdktools>
#include <multicolors>
#include <lvl_ranks>
#include <shop>

#pragma semicolon 1
#pragma newdecls required

#define PREFIX_MENU "[Bounty]"
#define PREFIX " \x04"... PREFIX_MENU ..."\x01"

// Enable plugin
ConVar g_cvPluginEnabled;

// General config settings
int g_DisplayMethod;
int g_XPRewardForBounty;
int g_RewardOnWarmup;
int g_MinNumOfPlayers;
int g_RewardTax;

// Header config settings
bool g_EnableHeader;
char g_HeaderPath[PLATFORM_MAX_PATH];

// Rewards from config
enum struct Reward
{
	int amount;
	char display[16];
}
ArrayList g_BountyRewards;

// Submitted bounties
enum struct Bounty
{
	int bounty_userid;
	int submitter_userid;
	int header_ent;
	Reward reward;
	
	void CreateHeader()
	{
		this.KillHeader();
		
		int client = GetClientOfUserId(this.bounty_userid);
		
		if (!client)
		{
			return;
		}
		
		char target_name[64];
		Format(target_name, sizeof(target_name), "client%i", client);
		DispatchKeyValue(client, "targetname", target_name);
		
		float pos[3];
		GetClientEyePosition(client, pos);
		pos[2] += 18.0;
		
		int ent = CreateEntityByName("env_sprite_oriented");
		if (ent)
		{
			DispatchKeyValue(ent, "model", g_HeaderPath);
			DispatchKeyValue(ent, "classname", "env_sprite");
			DispatchKeyValue(ent, "rendercolor", "255 255 255");
			DispatchSpawn(ent);
			
			TeleportEntity(ent, pos, NULL_VECTOR, NULL_VECTOR);
			
			SetVariantString("!activator");
			AcceptEntityInput(ent, "SetParent", client, ent, 0);
		}
			
		this.header_ent = EntIndexToEntRef(ent);
	}
	
	void KillHeader()
	{
		if (this.header_ent && this.header_ent != INVALID_ENT_REFERENCE && IsValidEdict(EntRefToEntIndex(this.header_ent)))
		{
			RemoveEdict(this.header_ent);
		}
	}
}
ArrayList g_Bounties;

public Plugin myinfo = 
{
	name = "[Shop Core] Bounty", 
	author = "LuqS", 
	description = "Lets players set a bounty on someones head.", 
	version = "1.0.0.0", 
	url = "https://steamcommunity.com/id/luqsgood || Discord: LuqS#6505"
}

public void OnPluginStart()
{
	g_Bounties = new ArrayList(sizeof(Bounty));
	g_BountyRewards = new ArrayList(sizeof(Reward));
	
	// Translations
	LoadTranslations("common.phrases");
	LoadTranslations("shop_bounty");
	
	// ConVars
	g_cvPluginEnabled = CreateConVar("sm_bounty_enable", "1", "if non zero, the plugin will be enabled.", _, true);
	g_cvPluginEnabled.AddChangeHook(PluginEnabled_Changed);
	
	// Events
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_disconnect", Event_PlayerDisconnect);
	
	// Commands
	RegConsoleCmd("sm_bl", Command_BountyList);
	RegConsoleCmd("sm_bounty", Command_OpenBountyMenu, "Opens the bounty menu.");
	
	if (Shop_IsStarted())
	{
		Shop_Started();
	}
}

// Shop intergration

public void Shop_Started()
{
	Shop_AddToFunctionsMenu(OnBountyShopDisplay, OnBountyShopSelect);
}

public void OnBountyShopDisplay(int client, char[] buffer, int maxlength)
{
	FormatEx(buffer, maxlength, "%t", "shop display string");
}

public bool OnBountyShopSelect(int client)
{
	return DisplayBountyOptionsMenu(client);
}

void RemoveFunctionFromShop()
{
	Shop_RemoveFromFunctionsMenu(OnBountyShopDisplay, OnBountyShopSelect);
}

// Commands

public Action Command_BountyList(int client, int args)
{
	DisplayBountyListMenu(client);
	return Plugin_Handled;
}

public Action Command_OpenBountyMenu(int client, int args)
{
	// Open menu to select a player and the amount of credits.
	DisplayPlayerSelectionBountyMenu(client);
	return Plugin_Handled;
}

// Menus

bool DisplayBountyOptionsMenu(int client)
{
	Menu bounty_options_menu = new Menu(BountyOptionsMenuHandler, MenuAction_Select | MenuAction_Cancel);
	bounty_options_menu.SetTitle("%s %t\n ", PREFIX_MENU, "bounty options menu title");
	
	char menu_buffer[256];
	
	Format(menu_buffer, sizeof(menu_buffer), "%t", "bounty list");
	bounty_options_menu.AddItem("", menu_buffer);
	
	Format(menu_buffer, sizeof(menu_buffer), "%t", "submit bounty");
	bounty_options_menu.AddItem("", menu_buffer);
	
	return bounty_options_menu.Display(client, MENU_TIME_FOREVER);
}

int BountyOptionsMenuHandler(Handle menu, MenuAction action, int client, int parm2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			switch (parm2)
			{
				case 0: // bounty list
				{
					DisplayBountyListMenu(client, true);
				}
				
				case 1: // add bounty
				{
					DisplayPlayerSelectionBountyMenu(client);
				}
			}
		}
		
		case MenuAction_Cancel:
		{
			Shop_ShowFunctionsMenu(client);
		}
		
		case MenuAction_End:
		{
			delete menu;
		}
	}
}


void DisplayBountyListMenu(int client, bool back_button = false)
{
	Menu bounty_list = new Menu(BountyListMenuHandler, MenuAction_Cancel);
	bounty_list.SetTitle("%s %t\n ", PREFIX_MENU, "bounty list menu title", g_RewardTax);
	
	char meun_buffer[216];
	if (g_Bounties.Length)
	{
		Bounty current_bounty_data;
		char submitter_name[MAX_NAME_LENGTH];
		for (int current_bounty = 0; current_bounty < g_Bounties.Length; current_bounty++)
		{
			current_bounty_data = GetBountyByIndex(current_bounty);
			
			int submitter = GetClientOfUserId(current_bounty_data.submitter_userid);
			if (submitter)
			{
				GetClientName(submitter, submitter_name, sizeof(submitter_name));
			}
			
			Format(meun_buffer, sizeof(meun_buffer), "%t", "bounty list menu item", GetClientOfUserId(current_bounty_data.bounty_userid), current_bounty_data.reward.display, submitter ? submitter_name : "Unknown");
			bounty_list.AddItem("", meun_buffer, ITEMDRAW_DISABLED);
		}
	}
	else
	{
		Format(meun_buffer, sizeof(meun_buffer), "%t", "no bounties");
		bounty_list.AddItem("", meun_buffer, ITEMDRAW_DISABLED);
	}
	
	bounty_list.ExitBackButton = back_button;
	bounty_list.Display(client, MENU_TIME_FOREVER);
}

int BountyListMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Cancel:
		{
			DisplayBountyOptionsMenu(param1);
		}
		
		case MenuAction_End:
		{
			delete menu;
		}
	}
}


void DisplayPlayerSelectionBountyMenu(int client)
{
	Menu player_bounty_menu = new Menu(BountyPlayerMenuHandler, MenuAction_Select);
	player_bounty_menu.SetTitle("%s %t\n ", PREFIX_MENU, "choose bounty player menu title");
	
	char current_client_name[MAX_NAME_LENGTH], current_client_userid[6];
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && current_client != client)
		{
			// Get userid and name
			IntToString(GetClientUserId(current_client), current_client_userid, sizeof(current_client_userid));
			GetClientName(current_client, current_client_name, sizeof(current_client_name));
			
			// Add to menu
			player_bounty_menu.AddItem(current_client_userid, current_client_name);
		}
	}
	
	if (!player_bounty_menu.ItemCount)
	{
		CPrintToChat(client, "%s %t", PREFIX, "no players in game");
	}
	
	player_bounty_menu.Display(client, MENU_TIME_FOREVER);
}

int BountyPlayerMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			// param1=client, param2=item
			int client = param1, item_pos = param2;
			
			char target_userid[6];
			menu.GetItem(item_pos, target_userid, sizeof(target_userid));
			
			int target = GetClientOfUserId(StringToInt(target_userid));
			if (!target)
			{
				CPrintToChat(client, "%s %t", PREFIX, "client disconnect after chosen");
				return;
			}
			
			DisplayRewardAmoutMenu(client, target_userid);
		}
		
		case MenuAction_End:
		{
			delete menu;
		}
	}
}


void DisplayRewardAmoutMenu(int client, char[] target_userid)
{
	Menu reward_bounty_menu = new Menu(BountyRewardMenuHandler, MenuAction_Select);
	reward_bounty_menu.SetTitle("%s %t\n ", PREFIX_MENU, "choose reward menu title", GetClientOfUserId(StringToInt(target_userid)));
	
	// save target to menu so we can use that later
	reward_bounty_menu.AddItem(target_userid, "", ITEMDRAW_IGNORE);
	
	// Add reward amounts from parsed config.
	char amount_str[16];
	Reward current_reward_data;
	for (int current_reward = 0; current_reward < g_BountyRewards.Length; current_reward++)
	{
		current_reward_data = GetRewardByIndex(current_reward);
		
		IntToString(current_reward_data.amount, amount_str, sizeof(amount_str));
		reward_bounty_menu.AddItem(amount_str, current_reward_data.display);
	}
	
	reward_bounty_menu.Display(client, MENU_TIME_FOREVER);
}

int BountyRewardMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			// param1=client, param2=item
			int client = param1, item_pos = param2;
			
			char target_userid[6];
			menu.GetItem(0, target_userid, sizeof(target_userid));
			
			int target = GetClientOfUserId(StringToInt(target_userid));
			if (!target)
			{
				CPrintToChat(client, "%s %t", PREFIX, "client disconnect after chosen");
				return;
			}
			
			char reward_str[16], reward_display[32];
			menu.GetItem(item_pos, reward_str, sizeof(reward_str), _, reward_display, sizeof(reward_display));
			
			int reward = StringToInt(reward_str);
			if (Shop_GetClientCredits(client) < reward)
			{
				CPrintToChat(client, "%s %t", PREFIX, "insufficient credits");
				return;
			}
			
			Shop_TakeClientCredits(client, reward);
			
			// Add bounty.
			Bounty new_bounty;
			new_bounty.reward = GetRewardByIndex(item_pos - 1);
			new_bounty.bounty_userid = GetClientUserId(target);
			new_bounty.submitter_userid = GetClientUserId(client);
			
			if (g_EnableHeader)
			{
				new_bounty.CreateHeader();
			}
			
			g_Bounties.PushArray(new_bounty);
			
			// Alert players there is a new bounty.
			switch (g_DisplayMethod)
			{
				case 1: CPrintToChatAll("%s %t", PREFIX, "new bounty message all", target, new_bounty.reward.display);
				case 2: PrintCenterTextAll("%t", "new bounty message all", target, new_bounty.reward.display);
			}
			
			SetHudTextParams(-1.0, 0.3, 10.0, 255, 0, 0, 255);
			ShowHudText(target, -1, "%t", "hud message target", client, new_bounty.reward.display);
		}
		
		case MenuAction_End:
		{
			delete menu;
		}
	}
}

// Events (Client)

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	// Plugin is not enabled or we don't want glow.
	if (!g_cvPluginEnabled.BoolValue || !g_EnableHeader)
	{
		return;
	}
	
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	int bounty_index = GetPlayerBountyIndex(client);
	if (bounty_index != -1)
	{
		Bounty bounty_data; bounty_data = GetBountyByIndex(bounty_index);
		bounty_data.CreateHeader();
		
		g_Bounties.SetArray(bounty_index, bounty_data);
	}
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvPluginEnabled.BoolValue || (!g_RewardOnWarmup && GameRules_GetProp("m_bWarmupPeriod")))
	{
		return;
	}
	
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	
	if (IsValidKill(victim, attacker))
	{
		// Check if a bounty player was killed.
		int bounty_index = GetPlayerBountyIndex(victim);
		if (bounty_index != -1)
		{
			Bounty current_bounty_data; current_bounty_data = GetBountyByIndex(bounty_index);
			
			// Kill VMT header
			current_bounty_data.KillHeader();
			
			// Check if the killer is not the subnitter, we don't allow XP farming here :D
			int submitter = GetClientOfUserId(current_bounty_data.submitter_userid);
			if (submitter && submitter == attacker)
			{
				return;
			}
			
			if (GetClientCount(true) < g_MinNumOfPlayers)
			{
				CPrintToChat(attacker, "%s %t", PREFIX, "bounty not claimed min players", g_MinNumOfPlayers);
				return;
			}
			
			// Show message
			switch (g_DisplayMethod)
			{
				case 1:CPrintToChatAll("%s %t", PREFIX, "bounty killed message all", attacker, current_bounty_data.reward.display, victim);
				case 2:PrintCenterTextAll("%t", "bounty killed message all", attacker, current_bounty_data.reward.display, victim);
			}
			
			// alert submitter that the player has died and tell him whoever killed him.
			if (submitter)
			{
				switch (g_DisplayMethod)
				{
					case 1:CPrintToChat(submitter, "%s %t", PREFIX, "submitter alert bounty confirmed", attacker, current_bounty_data.reward.display, victim);
					case 2:PrintCenterText(submitter, "%t", "submitter alert bounty confirmed", attacker, current_bounty_data.reward.display, victim);
				}
			}
			
			// Give credits
			Shop_GiveClientCredits(attacker, current_bounty_data.reward.amount - (current_bounty_data.reward.amount / g_RewardTax));
			
			// Give XP
			if (g_XPRewardForBounty)
			{
				LR_ChangeClientValue(attacker, g_XPRewardForBounty);
			}
			
			// remove bounty from arraylist.
			g_Bounties.Erase(bounty_index);
		}
	}
}

public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
	int bounty_index = GetPlayerBountyIndex(GetClientOfUserId(event.GetInt("userid")));
	if (bounty_index != -1)
	{
		RefundSubmitter(GetBountyByIndex(bounty_index), "refund submitter bounty disconnect");
		g_Bounties.Erase(bounty_index);
	}
}


// Events (Server)
public void OnMapStart()
{
	// Load KeyValues Config
	KeyValues kv = CreateKeyValues("Bounty");
	
	// Find the Config
	char file_path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, file_path, sizeof(file_path), "configs/shop/bounty.cfg");
	
	// Open file and go directly to the settings, if something doesn't work don't continue.
	if (!kv.ImportFromFile(file_path))
	{
		SetFailState("Couldn't load plugin config.");
	}
	
	// default no message
	g_DisplayMethod = kv.GetNum("display"); 
	
	// default no xp reward
	g_XPRewardForBounty = kv.GetNum("xp_reward"); 
	
	// Should the plugin reward players if they kill a bounty in the warmup period?
	g_RewardOnWarmup = kv.GetNum("reward_on_warmup"); 
	
	// minimum number of players to enable claim
	g_MinNumOfPlayers = kv.GetNum("min_players");
	
	if (kv.JumpToKey("header"))
	{
		g_EnableHeader = !!kv.GetNum("enable");
		
		kv.GetString("path", g_HeaderPath, sizeof(g_HeaderPath));
		
		// Reset KV tree
		kv.Rewind();
	}
	
	// reward tax
	g_RewardTax = kv.GetNum("reward_tax");
	
	// Parse Rewards one by one.
	if (kv.JumpToKey("rewards") && kv.GotoFirstSubKey(false))
	{
		Reward new_reward;
		do
		{
			if (kv.GetSectionName(new_reward.display, sizeof(Reward::display)))
			{
				new_reward.amount = kv.GetNum(NULL_STRING);
				g_BountyRewards.PushArray(new_reward);
			}
		} while (kv.GotoNextKey(false));
	}
	else
	{
		SetFailState("Couldn't find rewards in the plugin config.");
	}
	
	// Don't leak handles.
	kv.Close();
}

public void OnPluginEnd()
{
	RemoveFunctionFromShop();
	
	Bounty current_bounty_data;
	for (int current_bounty = 0; current_bounty < g_Bounties.Length; current_bounty++)
	{
		current_bounty_data = GetBountyByIndex(current_bounty);
		
		RefundSubmitter(current_bounty_data, "refund submitter plugin unload");
		
		current_bounty_data.KillHeader();
	}
	
	g_Bounties.Clear();
}

void PluginEnabled_Changed(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (StrEqual(newValue, "0"))
	{
		OnPluginEnd();
	}
}

// Other functions

bool IsValidKill(int client, int attacker)
{
	return (0 < client <= MaxClients && 0 < attacker <= MaxClients && GetClientTeam(client) != GetClientTeam(attacker));
}

// Returns player bounty index, -1 if not found.
int GetPlayerBountyIndex(int client)
{
	Bounty current_bounty_data;
	for (int current_bounty = 0; current_bounty < g_Bounties.Length; current_bounty++)
	{
		current_bounty_data = GetBountyByIndex(current_bounty);
		
		if (GetClientOfUserId(current_bounty_data.bounty_userid) == client)
		{
			return current_bounty;
		}
	}
	
	return -1;
}

void RefundSubmitter(Bounty bounty, const char[] message)
{
	int submitter = GetClientOfUserId(bounty.submitter_userid);
	if (submitter)
	{
		Shop_GiveClientCredits(submitter, bounty.reward.amount);
		
		CPrintToChat(submitter, "%s %t", PREFIX, message, bounty.reward.display);
	}
}

any[] GetBountyByIndex(int index)
{
	Bounty bounty;
	g_Bounties.GetArray(index, bounty, sizeof(bounty));
	
	return bounty;
}

any[] GetRewardByIndex(int index)
{
	Reward reward;
	g_BountyRewards.GetArray(index, reward, sizeof(reward));
	
	return reward;
} 