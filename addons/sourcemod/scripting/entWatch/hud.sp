#if !defined HUD
	#endinput
#endif

static Handle TimerHud;
static Handle CookieHud;
static bool Hud[MAXPLAYERS + 1];

void HudInit()
{
	CookieHud = RegClientCookie("entwatch_display", "", CookieAccess_Private);
	RegConsoleCmd("sm_hud", Command_Hud);
}

void HudOnMapStart()
{
	HudCreateTimer();
}

void HudOnMapEnd()
{
	TimerHud = null;
}

void HudCreateTimer()
{
	if(!Configs_Count)
		return;

	delete TimerHud;
	TimerHud = CreateTimer(1.0, Timer_Hud, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void HudOnClientPutInServer(int client)
{
	HudClientReadCookie(client);
}

void HudOnClientCookiesCached(int client)
{
	HudClientReadCookie(client);
}

void HudClientReadCookie(int client)
{
	if(!IsClientInGame(client))
		return;

	Hud[client] = true;
	
	if(IsFakeClient(client))
	{
		if(!IsClientSourceTV(client))
			Hud[client] = false;

		return;
	}


	if(AreClientCookiesCached(client))
	{
		char buffer[4];
		GetClientCookie(client, CookieHud, buffer, sizeof(buffer));
		if(buffer[0])
		{
			Hud[client] = !!(StringToInt(buffer));
		}
		else
		{
			Hud[client] = true;
		}
	}
}

void HudOnClientDisconnect(int client)
{
	Hud[client] = false;
}

void HudToggleClientHud(int client)
{
	Hud[client] = !Hud[client];
	PrintToChat2(client, "%t: %t", "Hud", Hud[client] ? "On":"Off");
	if(AreClientCookiesCached(client))
	{
		SetClientCookie(client, CookieHud, Hud[client] ? "1":"0");
	}
}

public Action Command_Hud(int client, int args)
{
	HudToggleClientHud(client);	
	return Plugin_Handled;
}

const int MAX_PAGES = 4;
const int TICKS_UPDATE_COUNT = 5;

public Action Timer_Hud(Handle hTimer)
{
    if(!Items_Count)
    	return Plugin_Continue;

    int pagesCount[3];
    char buffer[3][MAX_PAGES][256];
    char line[128];

    static int team;
    for (int i = 0; i < Items_Count; i++)
    {
    	if(!Items[i].Owner || !ConfigGetDisplay(Items[i].Config, DISPLAY_HUD))
    		continue;
    
    	team = GetClientTeam(Items[i].Owner) - 1;
    	ItemFormat(i, line, sizeof(line));
    	switch(team)
    	{
    		case 1, 2:
    		{
                if (strlen(buffer[team][pagesCount[team]]) + strlen(line) + 2 >= sizeof(buffer[][]))
    	            pagesCount[team]++;

                StrCat(buffer[team][pagesCount[team]], sizeof(buffer[][]), line);
    		}
    		default:
    		{
    			LogError("Timer_Hud() : owner item #%i isnt T or CT", Items[i].Config);
    			continue;
    		}
    	}

        if (strlen(buffer[0][pagesCount[0]]) + strlen(line) + 2 >= sizeof(buffer[][]))
            pagesCount[0]++;

        StrCat(buffer[0][pagesCount[0]], sizeof(buffer[][]), line);
    }

    static int currentPages[3];
    static int ticksUpdatePages;

    if(++ticksUpdatePages > TICKS_UPDATE_COUNT)
    {
		for(int i = 0; i < 3; i++)
		{
		    if(++currentPages[i] > pagesCount[i])
		        currentPages[i] = 0
		}
		
		ticksUpdatePages = 0;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
		if (!Hud[i])
			continue;
		
		team = GetClientTeam(i) - 1;
		
		if(team < 0)
			team = 0;
		
		if(!buffer[team][currentPages[team]][0])
			continue;
		
		Handle msg = StartMessageOne("KeyHintText", i);
		BfWriteByte(msg, 1);
		BfWriteString(msg, buffer[team][currentPages[team]]);
		EndMessage();
    }
    return Plugin_Continue;
}