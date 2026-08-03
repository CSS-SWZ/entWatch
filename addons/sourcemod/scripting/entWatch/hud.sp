#if !defined HUD
	#endinput
#endif

static bool hud_enabled;
static Handle TimerHud;
static Handle CookieHud;
static bool Hud[MAXPLAYERS + 1];

// Состояние ротации страниц. Живёт на уровне файла, а не в статиках Timer_Hud(),
// чтобы его можно было сбросить при смене карты.
static int HudCurrentPages[3];
static int HudTicksUpdate;

void HudInit()
{
	CookieHud = RegClientCookie("entwatch_display", "", CookieAccess_Private);
	RegConsoleCmd("sm_hud", Command_Hud);
}

void HudConfigLoad(KeyValues kv)
{
    hud_enabled = !!(kv.GetNum("hud", 1));
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
	delete TimerHud;

	// Номера страниц - состояние прошлой карты. Без сброса новая карта первые
	// секунды показывает страницу, которой у неё ещё нет.
	HudTicksUpdate = 0;

	for(int i = 0; i < sizeof(HudCurrentPages); i++)
	{
		HudCurrentPages[i] = 0;
	}

	if(!Configs_Count)
		return;

	if(!hud_enabled)
		return;

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
	// Пока cookies не загружены, переключать бессмысленно: сохранить выбор
	// некуда, а OnClientCookiesCached() тут же перезапишет его сохранённым
	// значением. Раньше это происходило молча.
	if(!AreClientCookiesCached(client))
	{
		PrintToChat2(client, "%t", "Cookies not loaded");
		return;
	}

	Hud[client] = !Hud[client];
	PrintToChat2(client, "%t: %t", "Hud", Hud[client] ? "On":"Off");
	SetClientCookie(client, CookieHud, Hud[client] ? "1":"0");
}

public Action Command_Hud(int client, int args)
{
	// AreClientCookiesCached() на нулевом индексе - ошибка натива,
	// да и переключать HUD серверной консоли нечего.
	if(client == 0)
	{
		ReplyToCommand(client, "%t %t", "Tag", "Command is in-game only");
		return Plugin_Handled;
	}

	HudToggleClientHud(client);
	return Plugin_Handled;
}

const int MAX_PAGES = 4;
const int MAX_PAGE_LENGTH = 256;
const int TICKS_UPDATE_COUNT = 5;

// Дописывает строку в постраничный буфер команды. Когда страницы кончились,
// строка отбрасывается: pagesCount за пределами MAX_PAGES - это обращение
// за границу buffer[][MAX_PAGES][MAX_PAGE_LENGTH].
void HudBufferAddLine(char buffer[][MAX_PAGE_LENGTH], int &pagesCount, const char[] line)
{
	if(strlen(buffer[pagesCount]) + strlen(line) + 2 >= MAX_PAGE_LENGTH)
	{
		if(pagesCount + 1 >= MAX_PAGES)
			return;

		pagesCount++;
	}

	StrCat(buffer[pagesCount], MAX_PAGE_LENGTH, line);
}

public Action Timer_Hud(Handle hTimer)
{
    if(!Items_Count)
    	return Plugin_Continue;

    int pagesCount[3];
    char buffer[3][MAX_PAGES][MAX_PAGE_LENGTH];
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
                HudBufferAddLine(buffer[team], pagesCount[team], line);
    		}
    		default:
    		{
    			LogError("Timer_Hud() : owner item #%i isnt T or CT", Items[i].Config);
    			continue;
    		}
    	}

        HudBufferAddLine(buffer[0], pagesCount[0], line);
    }

    // Строгое сравнение: с ">" период получался TICKS_UPDATE_COUNT + 1 секунда,
    // то есть константа означала не то, что написано в её имени.
    if(++HudTicksUpdate >= TICKS_UPDATE_COUNT)
    {
		for(int i = 0; i < 3; i++)
		{
		    if(++HudCurrentPages[i] > pagesCount[i])
		        HudCurrentPages[i] = 0;
		}

		HudTicksUpdate = 0;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
		if (!Hud[i])
			continue;
		
		team = GetClientTeam(i) - 1;
		
		if(team < 0)
			team = 0;
		
		if(!buffer[team][HudCurrentPages[team]][0])
			continue;
		
		Handle msg = StartMessageOne("KeyHintText", i);
		BfWriteByte(msg, 1);
		BfWriteString(msg, buffer[team][HudCurrentPages[team]]);
		EndMessage();
    }
    return Plugin_Continue;
}