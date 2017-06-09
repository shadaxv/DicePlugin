#include <sourcemod>
#include <sdktools>
#include <autoexecconfig>

#undef REQUIRE_PLUGIN
#include <updater>

#pragma semicolon 1

#define DICES 50
#define DICES2 21

new Handle:c_DiceText;
new Handle:c_ShowNumber;
new Handle:c_RandNumber;
new Handle:c_DiceTeam;
new Handle:c_DiceCount;
new Handle:c_DiceMoney;
new Handle:c_DiceMoney2;
Handle drug_loop2[MAXPLAYERS+1];

new String:DiceText[64];

new ShowNumber;
new RandNumber;
new DiceTeam;
new DiceMoney;
new DiceMoney2;
new DiceCount;

new UserMsg:g_FadeUserMsgId;

new friction_default = -1;
new accelerate_default = -1;

new NoclipCounter[MAXPLAYERS + 1];
new ClientDiced[MAXPLAYERS + 1];
new FroggyJumped[MAXPLAYERS + 1];
new fire[MAXPLAYERS + 1];

new bool:EnabledNumbers[DICES+1];
new bool:LongJump[MAXPLAYERS + 1];
new bool:Nightvision[MAXPLAYERS + 1];
new bool:FroggyJump[MAXPLAYERS + 1];
new bool:started;

public Plugin:myinfo =
{
	name = "Dice SM",
	author = "Popoklopsi",
	version = "1.6.2",
	description = "Roll the Dice by Popoklopsi",
	url = "https://forums.alliedmods.net/showthread.php?t=152035"
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	MarkNativeAsOptional("GetUserMessageType");

	return APLRes_Success;
}

public OnPluginStart()
{

	started = false;

	AutoExecConfig_SetFile("dice_config", "dice");
	AutoExecConfig_CreateConVar("dice_sm", "1.6.2", "Dice for Souremod by Popoklopsi", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	
	c_DiceText = AutoExecConfig_CreateConVar("dice_text", "dices", "Command to dice (without exclamation mark), convert to UTF-8 without BOM for special characters");
	c_ShowNumber = AutoExecConfig_CreateConVar("dice_show", "2", "Players, which see the result: 1 = Everybody, 2 = just T's, 3 = just CT's, 4 = Only you");
	c_RandNumber = AutoExecConfig_CreateConVar("dice_rand", "1", "1 = Random text when result is a weapon, 0 = Off");
	c_DiceTeam = AutoExecConfig_CreateConVar("dice_team", "2", "2 = Only T's can dice, 3 = Only CT's can dice, 0 = Everybody can dice");
	c_DiceCount = AutoExecConfig_CreateConVar("dice_count", "1", "How often a player can dice per round");
	c_DiceMoney = AutoExecConfig_CreateConVar("dice_money", "7000", "x = Money one dice costs, 0 = Off");
	c_DiceMoney2 = AutoExecConfig_CreateConVar("dice_money", "10000", "x = Money one dice costs, 0 = Off");

	AutoExecConfig_CleanFile();
	
	LoadEnables();

	AutoExecConfig(true, "dice_config", "dice");
	
	HookConVarChange(c_ShowNumber, OnConVarChanged);
	HookConVarChange(c_RandNumber, OnConVarChanged);
	HookConVarChange(c_DiceTeam, OnConVarChanged);
	
	HookEvent("player_spawn", PlayerSpawn);
	HookEvent("player_death", PlayerDeath);
	HookEvent("player_jump", PlayerJump);
	HookEvent("round_start", RoundStart);
	
	LoadTranslations("dice.phrases");
	
	g_FadeUserMsgId = GetUserMessageId("Fade");
}

public OnConfigsExecuted()
{
	decl String:ConsoleCmd[64];
	
	GetConVarString(c_DiceText, DiceText, sizeof(DiceText));
	
	ShowNumber = GetConVarInt(c_ShowNumber);
	RandNumber = GetConVarInt(c_RandNumber);
	DiceTeam = GetConVarInt(c_DiceTeam);
	DiceCount = GetConVarInt(c_DiceCount);
	DiceMoney = 7000;
	DiceMoney2 = 10000;
	accelerate_default = GetConVarInt(FindConVar("sv_accelerate"));
	friction_default = GetConVarInt(FindConVar("sv_friction"));
	
	if (!started)
	{
		Format(ConsoleCmd, sizeof(ConsoleCmd), "sm_ruletka");
		RegConsoleCmd(ConsoleCmd, TypedText);
		
		started = true;
	}
}

public OnAllPluginsLoaded()
{
	if (LibraryExists("updater"))
		Updater_AddPlugin("http://popoklopsi.de/dice/update.txt");
}

public OnLibraryAdded(const String:name[])
{
	if (StrEqual(name, "updater"))
		Updater_AddPlugin("http://popoklopsi.de/dice/update.txt");
}

public OnMapStart()
{
	PrecacheSound("weapons/rpg/rocketfire1.wav");
	PrecacheSound("weapons/rpg/rocket1.wav");
	PrecacheSound("weapons/hegrenade/explode3.wav");
	PrecacheModel("Effects/tp_eyefx/tp_eyefx.vmt");
	
	SetRandomSeed(RoundFloat(GetTime() +  GetRandomFloat(0.0, 1.0)));
}

public LoadEnables()
{
	decl String:section[5];
	
	new Handle:keycvar = CreateKeyValues("DiceEnables");
	
	if (FileExists("cfg/dice/dice_enables.txt") && FileToKeyValues(keycvar, "cfg/dice/dice_enables.txt"))
	{
		for (new x = 1; x <= DICES; x++)
		{
			Format(section, sizeof(section), "%i", x);
			
			if (KvGetNum(keycvar, section, 1) == 1)
				EnabledNumbers[x] = true;
			else
				EnabledNumbers[x] = false;
		}
	}
	else
	{
		for (new x = 1; x <= DICES; x++)
			EnabledNumbers[x] = true;
	}

	if (!getGame())
		EnabledNumbers[1] = false;
}

public Action:TypedText(client, args)
{
	if (client > 0 && client <= MaxClients && IsClientInGame(client))
		PrepareDice(client);
	
	return Plugin_Handled;
}

public OnConVarChanged(Handle:hCvar, const String:oldValue[], const String:newValue[])
{
	if (hCvar == c_ShowNumber) 
		ShowNumber = StringToInt(newValue);
		
	if (hCvar == c_RandNumber) 
		RandNumber = StringToInt(newValue);
		
	if (hCvar == c_DiceTeam) 
		DiceTeam = StringToInt(newValue);
}

public RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	new Handle:fr = FindConVar("sv_friction");
	new Handle:ac = FindConVar("sv_accelerate");

	if (GetConVarInt(fr) != friction_default && friction_default != -1)
		SetConVarInt(fr, friction_default, true, false);

	if (GetConVarInt(ac) != accelerate_default && accelerate_default != -1)
		SetConVarInt(ac, accelerate_default, true, false);
}

public PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if (IsPlayerAlive(client) && IsClientInGame(client))
	{
		PrintToChat(client, " \x2[\x0B%t\x2] \x04%t", "dice", "start");
		
		NoclipCounter[client] = 5;
		ClientDiced[client] = 0;
		FroggyJumped[client] = 0;
		Nightvision[client] = false;
		LongJump[client] = false;
		FroggyJump[client] = false;
		
		reset(client);
	}
}

public PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	reset(client);
}

public PlayerJump(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if (LongJump[client]) 
		longjump(client);
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client) || !FroggyJump[client])
		return Plugin_Continue;
	
	static bool:bPressed[MAXPLAYERS+1] = false;

	if(GetEntityFlags(client) & FL_ONGROUND)
	{
		FroggyJumped[client] = 0;
		bPressed[client] = false;
	}
	else
	{
		if (buttons & IN_JUMP)
		{
			if(!bPressed[client])
			{
				if(FroggyJumped[client]++ == 1)
					froggyjump(client);
			}

			bPressed[client] = true;
		}
		else
			bPressed[client] = false;
	}

	
	return Plugin_Continue;
}

public PrepareDice(client)
{
	decl String:Prefix[64];
	
	Format(Prefix, sizeof(Prefix), " \x2[\x0B%T\x2] \x04", "dice", client);

	new money = GetEntData(client, FindSendPropOffs("CCSPlayer", "m_iAccount"));
	
	if (!DiceTeam || GetClientTeam(client) == DiceTeam)
	{
		if (ClientDiced[client] < DiceCount)
		{
			if (IsPlayerAlive(client))
			{
				if (DiceMoney > 0)
				{
					if ((money - DiceMoney) >= 0)
					{
						SetEntData(client, FindSendPropOffs("CCSPlayer", "m_iAccount"), money - DiceMoney);

						ClientDiced[client]++;
						DiceNow(client);
					}
					else PrintToChat(client, "%s%t", Prefix, "money", DiceMoney);
				}
				else
				{
					ClientDiced[client]++;
					DiceNow(client);
				}
			}
			else PrintToChat(client, "%s%t", Prefix, "dead");
		}
		else PrintToChat(client, "%s%t", Prefix, "already", DiceCount);
	}
	
	else if (!DiceTeam || GetClientTeam(client) == 3)
	{
		if (ClientDiced[client] < DiceCount)
		{
			if (IsPlayerAlive(client))
			{
				if (DiceMoney2 > 0)
				{
					if ((money - 10000) >= 0)
					{
						SetEntData(client, FindSendPropOffs("CCSPlayer", "m_iAccount"), money - DiceMoney2);

						ClientDiced[client]++;
						DiceNow2(client);
					}
					else PrintToChat(client, "%s%t", Prefix, "money", DiceMoney2);
				}
				else
				{
					ClientDiced[client]++;
					DiceNow2(client);
				}
			}
			else PrintToChat(client, "%s%t", Prefix, "dead");
		}
		else PrintToChat(client, "%s%t", Prefix, "already", DiceCount);
	}
	
	else PrintToChat(client, "%s%t", Prefix, "wrong");
}

DiceNow(client)
{
	new number;
	new count;

	PrintToChat(client, " \x2[\x0B%t\x2] \x04%t", "dice", "rolling", ClientDiced[client], DiceCount);

	number = count = GetRandomInt(1, DICES);

	while(!EnabledNumbers[number])
	{
		if (number == DICES)
			number = 1;
		else
			number = number % DICES + 1;

		if (number == count)
			return;
	}

	switch (number)
	{
		case 1:
		{
			drunk(client);
		}
		case 2:
		{
			drug(client);
		}
		case 3:
		{
			new randomburn;
			randomburn = GetRandomInt(70, 110);
			burn(client, randomburn);
		}
		case 4:
		{
			new Float:randomspeed;
			randomspeed = float(GetRandomInt(115, 175)) / 100;
			speed(client, randomspeed);
		}
		case 5:
		{
			rocket(client);
		}
		case 7:
		{
			LongJump[client] = true;
		}
		case 8:
		{
			item(client, 1);
		}
		case 9:
		{
			new randomhealth1;
			randomhealth1 = GetRandomInt(20, 60);
			health(client, randomhealth1, 3);
		}
		case 10:
		{
			new randomhealth2;
			randomhealth2 = GetRandomInt(20, 65);
			health(client, randomhealth2, 2);
		}
		case 11:
		{
			new Float:randomspeed;
			randomspeed = float(GetRandomInt(50, 90)) / 100;
			speed(client, randomspeed);
		}
		case 12:
		{
			item(client, 2);
		}
		case 13:
		{
			item(client, 3);
		}
		case 15:
		{
			new Float:randomgravity1;
			randomgravity1 = float(GetRandomInt(40, 90)) / 100;
			gravity(client, randomgravity1);
		}
		case 16:
		{
			new Float:randomgravity2;
			randomgravity2 = float(GetRandomInt(40, 90)) / 100;
			gravity(client, randomgravity2);
		}
		case 17:
		{
			new randomhealth3;
			randomhealth3 = GetRandomInt(10, 60);
			new Float:randomspeed3;
			randomspeed3 = float(GetRandomInt(115, 175)) / 100;
			speed(client, randomspeed3);
			health(client, randomhealth3, 2);
		}
		case 18:
		{
			new randomhealth4;
			randomhealth4 = GetRandomInt(10, 40);
			new Float:randomgravity3;
			randomgravity3 = float(GetRandomInt(40, 90)) / 100;
			new Float:randomspeed4;
			randomspeed4 = float(GetRandomInt(55, 90)) / 100;
			health(client, randomhealth4, 3);
			gravity(client, randomgravity3);
			speed(client, randomspeed4);
		}
		case 19:
		{
			new randomhealth5;
			randomhealth5 = GetRandomInt(5, 40);
			new Float:randomgravity4;
			randomgravity4 = float(GetRandomInt(115, 200)) / 100;
			new Float:randomspeed5;
			randomspeed5 = float(GetRandomInt(60, 95)) / 100;
			gravity(client, randomgravity4);
			speed(client, randomspeed5);
			health(client, randomhealth5, 2);
		}
		case 20:
		{
			noclip(client, true, 5.0);
			
			PrintToChat(client, "[%t] %t", "dice", "noclip", NoclipCounter[client]);
			
			CreateTimer(1.0, NclipTimer, client, TIMER_REPEAT);
		}
		case 21:
		{
			new Float:randomfreeze;
			randomfreeze = float(GetRandomInt(10, 30));
			freeze(client, true, randomfreeze);
		}
		case 23:
		{
			item(client, 4);
		}
		case 24:
		{
			health(client, 1, 1);
		}
		case 25:
		{
			item(client, 5);
		}
		case 26:
		{
			FroggyJump[client] = true;
		}
		case 27:
		{
			Nightvision[client] = true;
		}
		case 31:
		{
			burn(client, 199);
			speed(client, 2.0);
			health(client, 100, 2);
		}
		case 34:
		{
			item(client, 6);
		}
		case 35:
		{
			item(client, 7);
		}
		case 36:
		{
			item(client, 8);
		}
		case 37:
		{
			item(client, 9);
		}
		case 38:
		{
			item(client, 10);
		}
		case 39:
		{
			item(client, 11);
		}
		case 40:
		{
			item(client, 12);
		}
		case 41:
		{
			item(client, 13);
		}
		case 42:
		{
			new money = GetEntData(client, FindSendPropOffs("CCSPlayer", "m_iAccount"));
			new randommoney;
			randommoney = (GetRandomInt(1, 9999));
			SetEntData(client, FindSendPropOffs("CCSPlayer", "m_iAccount"), money + randommoney);
		}
		case 43:
		{
			item(client, 14);
		}
		case 44:
		{
			shake(client, 120, 50, 30);
		}
		case 45:
		{
			rocket2(client);
		}
		case 46:
		{
			health(client, 300, 1);
			burn(client, 299);
			drug(client);
			shake(client, 120, 50, 30);
		}
		case 47:
		{
			PerformBlind(client, 255);
		}
		case 48:
		{
			PerformBlind(client, 240);
		}
		case 49:
		{
			PerformBlind(client, 210);
		}
		case 50:
		{
			RoseGlass(client, 210);
		}
	}
	
	ShowText(client, number);
}

DiceNow2(client)
{
	new number;

	PrintToChat(client, " \x2[\x0B%t\x2] \x04%t", "dice", "rolling", ClientDiced[client], DiceCount);

	number = GetRandomInt(1, DICES2);
	
	switch (number)
	{
		case 1:
		{
			new Float:randomfreeze;
			randomfreeze = float(GetRandomInt(1, 7));
			freeze(client, true, randomfreeze);
		}
		case 2:
		{
			item2(client, 1);
		}
		case 3:
		{
			item2(client, 2);
		}
		case 4:
		{
			item2(client, 3);
		}
		case 5:
		{
			item2(client, 4);
		}
		case 6:
		{
			item2(client, 5);
		}
		case 7:
		{
			item2(client, 6);
		}
		case 8:
		{
			new money = GetEntData(client, FindSendPropOffs("CCSPlayer", "m_iAccount"));
			new randommoney;
			randommoney = (GetRandomInt(1, 12999));
			SetEntData(client, FindSendPropOffs("CCSPlayer", "m_iAccount"), money + randommoney);
		}
		case 9:
		{
			Nightvision[client] = true;
		}
		case 10:
		{
			FroggyJump[client] = true;
		}
		case 11:
		{
			new Float:randomspeed;
			randomspeed = float(GetRandomInt(115, 130)) / 100;
			speed(client, randomspeed);
		}
		case 12:
		{
			new randomhealth;
			randomhealth = GetRandomInt(15, 50);
			health(client, randomhealth, 2);
		}
		case 13:
		{
			FroggyJump[client] = true;
			new Float:randomgravity;
			randomgravity = float(GetRandomInt(115, 150)) / 100;
			gravity(client, randomgravity);
		}
		case 14:
		{
			new randomhealth1;
			randomhealth1 = GetRandomInt(5, 30);
			health(client, randomhealth1, 3);
		}
		//case 15: - NIC
		case 16:
		{
			new Float:randomspeed1;
			randomspeed1 = float(GetRandomInt(75, 90)) / 100;
			speed(client, randomspeed1);
		}
		case 17:
		{
			new Float:randomgravity1;
			randomgravity1 = float(GetRandomInt(75, 90)) / 100;
			gravity(client, randomgravity1);
		}
		case 18:
		{
			item2(client, 7);
		}
		case 19:
		{
			shake(client, 45, 50, 30);
		}
		case 20:
		{
			PerformBlind(client, 210);
		}
		case 21:
		{
			RoseGlass(client, 210);
		}
	}
	
	ShowText2(client, number);
	
}

public Action:NclipTimer(Handle:timer, any:client)
{
	if (NoclipCounter[client] > 0 && IsPlayerAlive(client) && IsClientInGame(client))
	{
		PrintToChat(client, "[%t] %t", "dice", "noclip", NoclipCounter[client]);

		NoclipCounter[client]--;
		
		return Plugin_Continue;
	}
	
	noclip(client, false, 0.0);
	
	return Plugin_Stop;
}

ShowText(client, DiceNumber)
{
	decl String:Prefix[64];
	decl String:trans[10];
	decl String:trans_all[20];

	new clients[MAXPLAYERS + 1];
	new ClientCount = 0;

	Format(Prefix, sizeof(Prefix), " \x2[\x0B%T\x2] \x04", "dice", LANG_SERVER);

	Format(trans, sizeof(trans), "dice%i", DiceNumber);
	Format(trans_all, sizeof(trans_all), "dice%i_all", DiceNumber);
	
	if (ShowNumber != 4)
	{
		for (new x=1; x <= MaxClients; x++)
		{
			if (IsClientInGame(x))
			{
				if (ShowNumber == 1 || ShowNumber == GetClientTeam(x))
					clients[ClientCount++] = x;
			}
		}
	}
	else
	{
		clients[0] = client;
		ClientCount = 1;
	}
	
	//if ((DiceNumber == 8 || DiceNumber == 23 || DiceNumber == 25) && RandNumber == 1)
	//{
	//	while (DiceNumber == 8 || DiceNumber == 22 || DiceNumber == 24)
	//		DiceNumber = GetRandomInt(1, DICES);
	//		
	//	Format(trans, sizeof(trans), "dice%i", DiceNumber);
	//}

	//if ((DiceNumber == 32 || DiceNumber == 33) && ShowNumber != 1)
	//	PrintToChatAll("%s%t", Prefix, trans_all, DiceNumber);

	for (new x=0; x < ClientCount; x++)
		PrintToChat(clients[x], "%s%t", Prefix, trans, client, DiceNumber);
}

ShowText2(client, DiceNumber)
{
	decl String:Prefix[64];
	decl String:trans[10];
	decl String:trans_all[20];

	new clients[MAXPLAYERS + 1];
	new ClientCount = 0;

	Format(Prefix, sizeof(Prefix), " \x2[\x0B%T\x2] \x04", "dice", LANG_SERVER);

	Format(trans, sizeof(trans), "dicez%i", DiceNumber);
	Format(trans_all, sizeof(trans_all), "dice%i_all", DiceNumber);
	
	for (new x=1; x <= MaxClients; x++)
	{
		if (IsClientInGame(x))
		{
			if (GetClientTeam(x) == 3)
				clients[ClientCount++] = x;
		}
	}

	for (new x=0; x < ClientCount; x++)
		PrintToChat(clients[x], "%s%t", Prefix, trans, client, DiceNumber);
}

// PRESETS

public reset(client)
{ 
	if (!IsClientInGame(client)) 
		return;
	
	if(drug_loop2[client]!=INVALID_HANDLE)
	{
		KillTimer(drug_loop2[client]);
		drug_loop2[client]=INVALID_HANDLE;
	}
	
	new Float:pos[3];
	new Float:angs[3];
	
	gravity(client, 1.0);
	noclip(client, false, 0.0);
	freeze(client, false, 0.0);
	speed(client, 1.0);
	godmode(client, false);

	SetInvisible(client, true);
	SetOnFire(client, true);
	
	ExtinguishEntity(client);
	ClientCommand(client, "r_screenoverlay 0");
	
	GetClientAbsOrigin(client, pos);
	GetClientEyeAngles(client, angs);

	SetEntProp(client, Prop_Send, "m_iDefaultFOV", 90);
	
	angs[2] = 0.0;
	
	TeleportEntity(client, pos, angs, NULL_VECTOR);	
	
	new Handle:message = StartMessageOne("Fade", client, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS);
			
	if(GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf) 
	{
		PbSetInt(message, "duration", 1536);
		PbSetInt(message, "hold_time", 1536);
		PbSetInt(message, "flags", (0x0001 | 0x0010));
		PbSetColor(message, "clr", {0, 0, 0, 0});
	}
	else
	{
		BfWriteShort(message, 1536);
		BfWriteShort(message, 1536);
		BfWriteShort(message, (0x0001 | 0x0010));
		BfWriteByte(message, 0);
		BfWriteByte(message, 0);
		BfWriteByte(message, 0);
		BfWriteByte(message, 0);
	}

	EndMessage();
	
	message = StartMessageOne("Shake", client, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS);

	if(GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf) 
	{
		PbSetInt(message, "command", 1);
		PbSetFloat(message, "local_amplitude", 0.0);
		PbSetFloat(message, "frequency", 0.0);
		PbSetFloat(message, "duration", 1.0);
	}
	else
	{
		BfWriteByte(message, 1);
		BfWriteFloat(message, 0.0);
		BfWriteFloat(message, 0.0);
		BfWriteFloat(message, 1.0);
	}
	
	EndMessage();

}

PerformBlind(client, amount)
{
	new targets[2];
	targets[0] = client;
	
	new duration = 1536;
	new holdtime = 1536;
	new flags;
	if (amount == 0)
	{
		flags = (0x0001 | 0x0010);
	}
	else
	{
		flags = (0x0002 | 0x0008);
	}
	
	new color[4] = { 0, 0, 0, 0 };
	color[3] = amount;
	
	Handle message = StartMessageEx(g_FadeUserMsgId, targets, 1);
	if (GetUserMessageType() == UM_Protobuf)
	{
		Protobuf pb = UserMessageToProtobuf(message);
		pb.SetInt("duration", duration);
		pb.SetInt("hold_time", holdtime);
		pb.SetInt("flags", flags);
		pb.SetColor("clr", color);
	}
	else
	{
		BfWrite bf = UserMessageToBfWrite(message);
		bf.WriteShort(duration);
		bf.WriteShort(holdtime);
		bf.WriteShort(flags);		
		bf.WriteByte(color[0]);
		bf.WriteByte(color[1]);
		bf.WriteByte(color[2]);
		bf.WriteByte(color[3]);
	}
	
	EndMessage();
}

RoseGlass(client, amount)
{
	new targets[2];
	targets[0] = client;
	
	new duration = 1536;
	new holdtime = 1536;
	new flags;
	if (amount == 0)
	{
		flags = (0x0001 | 0x0010);
	}
	else
	{
		flags = (0x0002 | 0x0008);
	}
	
	new color[4] = { 255, 0, 102, 0 };
	color[3] = amount;
	
	Handle message = StartMessageEx(g_FadeUserMsgId, targets, 1);
	if (GetUserMessageType() == UM_Protobuf)
	{
		Protobuf pb = UserMessageToProtobuf(message);
		pb.SetInt("duration", duration);
		pb.SetInt("hold_time", holdtime);
		pb.SetInt("flags", flags);
		pb.SetColor("clr", color);
	}
	else
	{
		BfWrite bf = UserMessageToBfWrite(message);
		bf.WriteShort(duration);
		bf.WriteShort(holdtime);
		bf.WriteShort(flags);		
		bf.WriteByte(color[0]);
		bf.WriteByte(color[1]);
		bf.WriteByte(color[2]);
		bf.WriteByte(color[3]);
	}
	
	EndMessage();
}

public longjump(client)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client)) 
		return;
	
	new Float:velocity[3];
	new Float:velocity0;
	new Float:velocity1;
	
	velocity0 = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[0]");
	velocity1 = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[1]");
	
	velocity[0] = (7.0 * velocity0) * (1.0 / 4.1);
	velocity[1] = (7.0 * velocity1) * (1.0 / 4.1);
	velocity[2] = 0.0;
	
	SetEntPropVector(client, Prop_Send, "m_vecBaseVelocity", velocity);
}

public froggyjump(client)
{
	new Float:velocity[3];
	new Float:velocity0;
	new Float:velocity1;
	new Float:velocity2;
	new Float:velocity2_new;

	velocity0 = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[0]");
	velocity1 = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[1]");
	velocity2 = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[2]");

	velocity2_new = 260.0;

	if (velocity2 < 150.0) 
		velocity2_new = 270.0;
	if (velocity2 < 100.0) 
		velocity2_new = 300.0;
	if (velocity2 < 50.0) 
		velocity2_new = 330.0;
	if (velocity2 < 0.0) 
		velocity2_new = 380.0;
	if (velocity2 < -50.0) 
		velocity2_new = 400.0;
	if (velocity2 < -100.0) 
		velocity2_new = 430.0;
	if (velocity2 < -150.0) 
		velocity2_new = 450.0;
	if (velocity2 < -200.0) 
		velocity2_new = 470.0;

	velocity[0] = velocity0 * 0.1;
	velocity[1] = velocity1 * 0.1;
	velocity[2] = velocity2_new;
	
	SetEntPropVector(client, Prop_Send, "m_vecBaseVelocity", velocity);
}

public OnGameFrame()
{
	for (new i = 1; i < MaxClients + 1; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && Nightvision[i])
			SetEntProp(i, Prop_Send, "m_bNightVisionOn", 1);
	}
}

public SetInvisible(client, bool:visible)
{
	new weapon;	

	new RenderMode:mode;
	new alpha;

	if (visible)
	{
		mode = RENDER_NORMAL;
		alpha = 255;
	}
	else
	{
		mode = RENDER_TRANSCOLOR;
		alpha = 20;
	}

	for (new i = 0; i < 4; i++)
	{
		if ((weapon = GetPlayerWeaponSlot(client, i)) != -1)
		{
			SetEntityRenderMode(weapon, mode);
			SetEntityRenderColor(weapon, 255, 255, 255, alpha);
		}
	}

	SetEntityRenderColor(client, 255, 255, 255, alpha);
	SetEntityRenderMode(client, mode);
}

public SetOnFire(client, bool:extinguish)
{
	if (fire[client] != 0) 
	{
		if (IsValidEntity(fire[client]))
		{
			decl String:class[128];
			
			GetEdictClassname(fire[client], class, sizeof(class));
			
			if (StrEqual(class, "env_fire")) 
				RemoveEdict(fire[client]);
		}
		
		fire[client] = 0;
	}

	if (!extinguish)
		CreateTimer(2.0, SetOnFireTimer, client);
}

public Action:SetOnFireTimer(Handle:timer, any:client)
{
	if (IsClientInGame(client))
	{
		if ((GetClientTeam(client) == 2 || GetClientTeam(client) == 3) && IsPlayerAlive(client))
		{
			new view = CreateEntityByName("env_fire");
			
			if (view != -1)
			{
				DispatchKeyValue(view, "ignitionpoint", "0");
				DispatchKeyValue(view, "spawnflags", "285");
				DispatchKeyValue(view, "fireattack", "0");
				DispatchKeyValue(view, "firesize", "512");
				DispatchKeyValueFloat(view, "damagescale", 0.0);
				
				if (DispatchSpawn(view))
				{
					decl Float:origin[3];
					decl String:steamid[20];
					
					if (IsValidEntity(view))
					{
						fire[client] = view;
						
						GetClientAbsOrigin(client, origin);
						
						TeleportEntity(view, origin, NULL_VECTOR, NULL_VECTOR);

						origin[2] = origin[2] + 90;

						AcceptEntityInput(view, "StartFire");
						
						GetClientAuthString(client, steamid, sizeof(steamid));
						DispatchKeyValue(client, "targetname", steamid);
						
						SetVariantString(steamid);
						AcceptEntityInput(view, "SetParent");
					}
				}
			}
		}
	}
}

public gravity(client, Float:amount)
{
	SetEntityGravity(client, amount);
}

public item(client, type)
{
	switch(type)
	{
		case 1:
		{
			GivePlayerItem(client, "weapon_deagle");
		}
		case 2:
		{
			GivePlayerItem(client, "weapon_hegrenade");
		}
		case 3:
		{
			GivePlayerItem(client, "weapon_flashbang");
			GivePlayerItem(client, "weapon_flashbang");
		}
		case 4:
		{
			GivePlayerItem(client, "weapon_glock");
		}
		case 5:
		{
			if (getGame())
				GivePlayerItem(client, "weapon_m3");
			else
				GivePlayerItem(client, "weapon_sawedoff");
		}
		case 6:
		{
			GivePlayerItem(client, "weapon_healthshot");
		}
		case 7:
		{
			GivePlayerItem(client, "weapon_healthshot");
			GivePlayerItem(client, "weapon_decoy");
		}
		case 8:
		{
			GivePlayerItem(client, "weapon_smokegrenade");
		}
		case 9:
		{
			GivePlayerItem(client, "weapon_molotov");
		}
		case 10:
		{
			GivePlayerItem(client, "weapon_flashbang");
		}
		case 11:
		{
			GivePlayerItem(client, "weapon_taser");
		}
		case 12:
		{
			GivePlayerItem(client, "weapon_decoy");
		}
		case 13:
		{
			GivePlayerItem(client, "weapon_decoy");
			GivePlayerItem(client, "weapon_flashbang");
		}
		case 14:
		{
			GivePlayerItem(client, "item_heavyassaultsuit");
		}
	}
}

public item2(client, type)
{
	switch(type)
	{
		case 1:
		{
			GivePlayerItem(client, "weapon_healthshot");
		}
		case 2:
		{
			GivePlayerItem(client, "weapon_healthshot");
			GivePlayerItem(client, "weapon_decoy");
		}
		case 3:
		{
			GivePlayerItem(client, "weapon_decoy");
		}
		case 4:
		{
			GivePlayerItem(client, "weapon_taser");
		}
		case 5:
		{
			GivePlayerItem(client, "weapon_taser");
			GivePlayerItem(client, "weapon_decoy");
		}
		case 6:
		{
			GivePlayerItem(client, "weapon_revolver");
		}
		case 7:
		{
			GivePlayerItem(client, "item_heavyassaultsuit");
		}
	}
}
	
	

public bool:getGame()
{
	decl String:game[64];

	GetGameFolderName(game, sizeof(game));

	return (StrEqual(game, "cstrike", false));
}

public noclip(client, bool:turnOn, Float:time)
{
	if (IsClientInGame(client))
	{
		if (turnOn)
		{
			SetEntityMoveType(client, MOVETYPE_NOCLIP);
		}
		else
			SetEntityMoveType(client, MOVETYPE_WALK);
	}
}

public freeze(client, bool:turnOn, Float:time)
{	
	if (IsClientInGame(client))
	{
		if (turnOn)
		{
			SetEntityMoveType(client, MOVETYPE_NONE);
			
			if (time > 0) 
				CreateTimer(time, freezeOff, client);
		}
		else
			SetEntityMoveType(client, MOVETYPE_WALK);
	}
}

public health(client, amount, type)
{
	switch(type)
	{
		case 1:
		{
			SetEntityHealth(client, amount);
		}
		case 2:
		{
			SetEntityHealth(client, GetClientHealth(client) + amount);
		}
		case 3:
		{
			new nhealth = GetClientHealth(client) - amount;

			if (nhealth <= 0)
				ForcePlayerSuicide(client);
			else
				SetEntityHealth(client, nhealth);
		}
	}
}

public drunk(client)
{
	ClientCommand(client, "r_screenoverlay Effects/tp_eyefx/tp_eyefx.vmt");
}

public drug(client)
{
	drug_loop2[client] = CreateTimer(1.0, drug_loop, client, TIMER_REPEAT);	
}

public burn(client, health)
{
	new Float:time = float(health) / 5.0;
	
	if (health < 100) 
		IgniteEntity(client, time);
	else 
		IgniteEntity(client, 100.0);
}

public speed(client, Float:speed)
{
	SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", speed); 
}

public rocket(client)
{
	new Float:Origin[3];
	
	GetClientAbsOrigin(client, Origin);
	
	Origin[2] = Origin[2] + 20;
	
	godmode(client, true);
	shake(client, 10, 40, 25);
	
	EmitSoundToAll("weapons/rpg/rocketfire1.wav", client, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.5);
	
	CreateTimer(1.0, PlayRocketSound, client);
	CreateTimer(3.1, EndRocket, client);
}

public rocket2(client)
{
	new Float:Origin[3];
	
	GetClientAbsOrigin(client, Origin);
	
	Origin[2] = Origin[2] + 20;

	shake(client, 10, 40, 25);
	
	EmitSoundToAll("weapons/rpg/rocketfire1.wav", client, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.5);
	
	CreateTimer(1.0, PlayRocketSound, client);
	CreateTimer(2.6, EndRocket2, client);
}

public godmode(client, bool:turnOn)
{
	if (turnOn) 
		SetEntProp(client, Prop_Data, "m_takedamage", 0, 1);
	else
		SetEntProp(client, Prop_Data, "m_takedamage", 2, 1);
}

stock shake(client, time, distance, value)
{
	new Handle:message = StartMessageOne("Shake", client, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS);

	if(GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf) 
	{
		PbSetInt(message, "command", 0);
		PbSetFloat(message, "local_amplitude", float(value));
		PbSetFloat(message, "frequency", float(distance));
		PbSetFloat(message, "duration", float(time));
	}
	else
	{
		BfWriteByte(message, 0);
		BfWriteFloat(message, float(value));
		BfWriteFloat(message, float(distance));
		BfWriteFloat(message, float(time));
	}
	
	EndMessage();	
}

public Action:PlayRocketSound(Handle:timer, any:client)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client)) 
		return;
	
	new Float:Origin[3];
	
	GetClientAbsOrigin(client, Origin);
	
	Origin[2] = Origin[2] + 50;
	
	EmitSoundToAll("weapons/rpg/rocket1.wav", client, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.5);
	
	for (new x=1; x <= 15; x++) 
		CreateTimer(0.2*x, rocket_loop, client);
	
	TeleportEntity(client, Origin, NULL_VECTOR, NULL_VECTOR);
}

public Action:EndRocket(Handle:timer, any:client)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
		return Plugin_Stop;
	
	new Float:Origin[3];
	
	GetClientAbsOrigin(client, Origin);
	
	Origin[2] = Origin[2] + 50;
	
	for (new x=1; x <= MaxClients; x++)
	{
		if (IsClientConnected(x)) 
			StopSound(x, SNDCHAN_AUTO, "weapons/rpg/rocket1.wav");
	}
	
	EmitSoundToAll("weapons/hegrenade/explode3.wav", client, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.5);
	
	new expl = CreateEntityByName("env_explosion");
	
	TeleportEntity(expl, Origin, NULL_VECTOR, NULL_VECTOR);
	
	DispatchKeyValue(expl, "fireballsprite", "sprites/zerogxplode.spr");
	DispatchKeyValue(expl, "spawnflags", "0");
	DispatchKeyValue(expl, "iMagnitude", "1000");
	DispatchKeyValue(expl, "iRadiusOverride", "100");
	DispatchKeyValue(expl, "rendermode", "0");
	
	DispatchSpawn(expl);
	ActivateEntity(expl);
	
	AcceptEntityInput(expl, "Explode");
	AcceptEntityInput(expl, "Kill");
	
	godmode(client, false);
	ForcePlayerSuicide(client);

	return Plugin_Handled;
}

public Action:EndRocket2(Handle:timer, any:client)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
		return Plugin_Stop;
	
	new Float:Origin[3];
	
	GetClientAbsOrigin(client, Origin);
	
	Origin[2] = Origin[2] + 50;
	
	for (new x=1; x <= MaxClients; x++)
	{
		if (IsClientConnected(x)) 
			StopSound(x, SNDCHAN_AUTO, "weapons/rpg/rocket1.wav");
	}

	return Plugin_Handled;
}

public Action:drug_loop(Handle:timer, any:client)
{
	if (!IsClientInGame(client)) 
		return Plugin_Stop;
	
	new Float:DrugAngles[29] = {0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 90.0, -90.0, 180.0, -180.0, -1.0, -2.0, -3.0, -4.0, -5.0, -6.0, -7.0, -8.0, -9.0, -10.0, -11.0, -12.0};

	if (!IsPlayerAlive(client))
	{
		new Float:pos[3];
		new Float:angs[3];
		
		GetClientAbsOrigin(client, pos);
		GetClientEyeAngles(client, angs);
		
		angs[2] = 0.0;
		
		TeleportEntity(client, pos, angs, NULL_VECTOR);	
		
		new Handle:message = StartMessageOne("Fade", client, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS);
		
		if(GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf) 
		{
			PbSetInt(message, "duration", 1536);
			PbSetInt(message, "hold_time", 1536);
			PbSetInt(message, "flags", (0x0001 | 0x0010));
			PbSetColor(message, "clr", {0, 0, 0, 0});
		}
		else
		{
			BfWriteShort(message, 1536);
			BfWriteShort(message, 1536);
			BfWriteShort(message, (0x0001 | 0x0010));
			BfWriteByte(message, 0);
			BfWriteByte(message, 0);
			BfWriteByte(message, 0);
			BfWriteByte(message, 0);
		}
		
		EndMessage();	
		
		return Plugin_Stop;
	}
	
	new Float:pos[3];
	new Float:angs[3];
	new coloring[4];

	coloring[0] = GetRandomInt(0,255);
	coloring[1] = GetRandomInt(0,255);
	coloring[2] = GetRandomInt(0,255);
	coloring[3] = 128;
	
	GetClientAbsOrigin(client, pos);
	GetClientEyeAngles(client, angs);
	
	angs[2] = DrugAngles[GetRandomInt(0,100) % 25];
	
	TeleportEntity(client, pos, angs, NULL_VECTOR);

	new Handle:message = StartMessageOne("Fade", client);

	if(GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf) 
	{
		PbSetInt(message, "duration", 255);
		PbSetInt(message, "hold_time", 255);
		PbSetInt(message, "flags", (0x0002));
		PbSetColor(message, "clr", coloring);
	}
	else
	{
		BfWriteShort(message, 255);
		BfWriteShort(message, 255);
		BfWriteShort(message, (0x0002));
		BfWriteByte(message, GetRandomInt(0,255));
		BfWriteByte(message, GetRandomInt(0,255));
		BfWriteByte(message, GetRandomInt(0,255));
		BfWriteByte(message, 128);
	}
	
	EndMessage();	
		
	return Plugin_Handled;
}

public Action:rocket_loop(Handle:timer, any:client)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
		return Plugin_Stop;
		
	new Float:velocity[3];
	
	velocity[2] = 300.0;
	
	TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, velocity);
	
	return Plugin_Handled;
}

public Action:freezeOff(Handle:timer, any:client)
{
	freeze(client, false, 0.0);
	
	return Plugin_Handled;
}