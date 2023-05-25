/* assist_use - это модуль, помогающий игрокам использовать материи.
Традиционный метод использования материи не гарантирует, что игрок точно заюзает материю
Ситуации, когда материю не получается использовать: прицел упирается в стену, не сделан прыжок перед использованием (для смещения кнопки)
Задача модуля форсированно нажать за игрока кнопку, если игрок нажал на Е
Проблема #1 это нажатие кнопки материи и нажатие кнопки карты (триггер)
Проблема #2 это возможность карты иметь несколько материй для игрока (ze_castlevania, ze_paranoid)*/

/* 
Событие, когда игрок активирует кнопку func_button. 
Здесь записывается время активации кнопки если эта кнопка не от айтема
Задача предупредить ситуацию, когда игрок будучи с айтемом хочет нажать на кнопку (сделать триггер) и вместе с ним активируется материя
*/

#if !defined ASSIST_USE
	#endinput
#endif

#define ASSIST_USE_CD    0.1

bool AssistUse_Toggle;

float PressButtonTime[MAXPLAYERS + 1];
float AssistUseTime[MAXPLAYERS + 1];

void AssistUseInit()
{
	RegAdminCmd("sm_assistuse", Command_AssistUse, ADMFLAG_RCON);
	RegAdminCmd("sm_euse", Command_Use, ADMFLAG_BAN);
	HookEntityOutput("func_button", "OnPressed", AssistUseOnButtonPressed);
	HookEntityOutput("func_door", "OnOpen", AssistUseOnDoorOpen);
	HookEntityOutput("func_door_rotating", "OnOpen", AssistUseOnDoorOpen);
}

public Action Command_AssistUse(int client, int args)
{
	AssistUse_Toggle = !AssistUse_Toggle;
	PrintToChat2(client, "Assist use: %s", AssistUse_Toggle ? "On":"Off");
	return Plugin_Handled;
}

public Action Command_Use(int client, int args)
{
	if (args != 1)
	{
		ReplyToCommand(client, "%t %t!\nSyntax: sm_euse <owner/$item>", "Tag", "Incorrect usage");
		return Plugin_Handled;
	}
		
	int item = -1;
	char buffer[64];
	GetCmdArg(1, buffer, sizeof(buffer));
	bool mode = (buffer[0] != '$');
		
	if(mode)
	{
		int target = FindTarget(client, buffer, true, false);
		
		if(target == -1)
		    return Plugin_Handled;
		
		while((item = ItemFindClientItem(target, item)) != -1)
		{
		    if(!AssistUseAdmin(item, client))
		        continue;
		
		    break;
		}
		
		return Plugin_Handled;
	}
		
	item = ItemsGetByShortName(buffer[1]);
	AssistUseAdmin(item, client);
	return Plugin_Handled;
}

stock bool AssistUseAdmin(int item, int admin)
{
	if(!Items[item].Button || !Items[item].Owner)
		return false;

	bool showUse = ConfigGetDisplay(Items[item].Config, DISPLAY_USE);

	Configs[Items[item].Config].Display &= ~(DISPLAY_USE);

	bool result = AssistUse(item);

	if(showUse)
	{
		Configs[Items[item].Config].Display |= DISPLAY_USE;
	}
	if(result)
	{
		PrintToTeam(GetClientTeam(Items[item].Owner), "\x07%s%N \x07%s%t \x07%s%s", Colors[COLOR_NAME], admin, Colors[COLOR_OTHER], "Assist use admin", Configs[Items[item].Config].Color[1], Configs[Items[item].Config].Name);
		return true;
	}
	return false;
}

void AssistUseConfigLoad(KeyValues kv)
{
    AssistUse_Toggle = !!(kv.GetNum("assist_use", 1));
}

public void AssistUseOnDoorOpen(const char[] output, int caller, int activator, float delay)
{
	if(!AssistUse_Toggle)
		return;

	int client = GetEntPropEnt(caller, Prop_Data, "m_hActivator");

	if(client <= 0 || client > MaxClients)
		return;

	PressButtonTime[client] = GetGameTime();
}

public void AssistUseOnButtonPressed(const char[] output, int caller, int activator, float delay)
{
	if(!AssistUse_Toggle || activator < 0 || activator > MaxClients || !caller)
		return;

	PressButtonTime[activator] = GetGameTime();
}

void AssistUseOnPlayerRunCmdPost(int client, int buttons)
{
	if(!RoundStarted)
		return;

	if(!AssistUse_Toggle)
		return;

	static int prevButtons[MAXPLAYERS + 1];
	if(prevButtons[client] & IN_USE || !(buttons & IN_USE))
	{
		prevButtons[client] = buttons;
		return;
	}

	if(RestrictClientHasRestrict(client))
	    return;
	
	float tick = GetTickInterval();
	float time = GetGameTime();
	float diffUseAssist = time - AssistUseTime[client];
	float diffAnyUse = time - PressButtonTime[client];

	if(diffUseAssist <= ASSIST_USE_CD || diffAnyUse <= tick)
	{
		prevButtons[client] = buttons;
		return;
	}
	AssistUseTime[client] = time;
	if(!AssistUseIsValidTarget(client))
	{
		prevButtons[client] = buttons;
		return;
	}

	int item = AssistUseFindClientItem(client);

	if(item != -1)
		AssistUse(item);

	prevButtons[client] = buttons;
}

bool AssistUse(int item)
{
	if(!Items[item].Button)
		return false;

	return AssistUseInputByName(item);
}

bool AssistUseInputByName(int item)
{
	char classname[64];
		
	if(!GetEntityClassname(Items[item].Button, classname, sizeof(classname)))
	    return false;

	if(strncmp(classname, "func_button", 11, false) == 0)
	{
		AcceptEntityInput(Items[item].Button, "Use", Items[item].Owner, Items[item].Owner);
		//AcceptEntityInput(Items[item].Button, "PressIn", Items[item].Owner, Items[item].Owner);
		return true;
	}
	if(strncmp(classname, "func_rot_button", 15, false) == 0)
	{
		AcceptEntityInput(Items[item].Button, "Use", Items[item].Owner, Items[item].Owner);
		//AcceptEntityInput(Items[item].Button, "PressIn", Items[item].Owner, Items[item].Owner);
		return true;
	}

	if(strncmp(classname, "func_physbox_multiplayer", 24, false) == 0)
	{
		//AcceptEntityInput(Items[item].Button, "Use", Items[item].Owner, Items[item].Owner);
		//FireEntityOutput(Items[item].Button, "OnPlayerUse", Items[item].Owner);
		return false;
	}
	if(strncmp(classname, "func_door", 9, false) == 0)
	{
		AcceptEntityInput(Items[item].Button, "Use", Items[item].Owner, Items[item].Owner);
		//AcceptEntityInput(Items[item].Button, "Open", Items[item].Owner, Items[item].Owner);
		return true;
	}
	
	LogError("AssistUse(item = %i) : classname=%s W=%i, B=%i (wpn hammerid = %i)", item, classname, Items[item].Weapon, Items[item].Button, GetEntProp(Items[item].Weapon, Prop_Data, "m_iHammerID"));
	return false;
}

void AssistUseOnClientDisconnect(int client)
{
	PressButtonTime[client] = 0.0;
	AssistUseTime[client] = 0.0;
}

/* Проверка, не смотрит ли игрок в кнопку или дверь */

bool AssistUseIsValidTarget(int client)
{
	char classname[64];
	float origin[3], angles[3];

	GetClientEyePosition(client, origin); 
	GetClientEyeAngles(client, angles);
	TR_TraceRayFilter(origin, angles, MASK_SOLID, RayType_Infinite, TraceFilter);

	int target = TR_GetEntityIndex();

	if(target <= MaxClients || !IsValidEntity(target) || ItemsGetByButton(target) != -1 || !GetEntityClassname(target, classname, sizeof(classname)))
		return true;

	if(StrContains(classname, "button", false) != -1)
		return false;

	if(StrContains(classname, "door", false) != -1)
	{
		int flags = GetEntProp(target, Prop_Data, "m_spawnflags");

		if(flags & 256) // Door can be opened by pressing E
		{
			return false;
		}
	}

	return true;
}

public bool TraceFilter(int value, int value2)
{
	return (value > MaxClients);
}

stock int AssistUseFindClientItem(int client)
{
	int item = -1;

	while((item = ItemFindClientItem(client, item)) != -1)
	{
		if(Items[item].Button)
			return item;
	}

	return -1;
}