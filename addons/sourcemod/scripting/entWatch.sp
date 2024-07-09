#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <clientprefs>

#include <entWatch>

#pragma newdecls required

#define ASSIST_USE
#define ADMIN_MENU
#define HALFZOMBIE

bool Late;

#include "entWatch/database.sp"
#include "entWatch/colors.sp"
#include "entWatch/config.sp"
#include "entWatch/items.sp"
#include "entWatch/client.sp"
#include "entWatch/chat.sp"
#include "entWatch/assist_use.sp"
#include "entWatch/halfzombie.sp"
#include "entWatch/sdkhook.sp"
#include "entWatch/dump.sp"
#include "entWatch/hud.sp"
#include "entWatch/restrict.sp"
#include "entWatch/transfer.sp"
#include "entWatch/helpers.sp"
#include "entWatch/admin_menu.sp"
#include "entWatch/spawn.sp"
#include "entWatch/api.sp"
#include "entWatch/stripper.sp"

public Plugin myinfo =
{
    name = "entWatch",
    author = "hEl",
    description = "Provides useful features with map items",
    version = "1.0",
    url = "https://github.com/CSS-SWZ/entWatch"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    Late = late;

    APIInit();
    RegPluginLibrary("entWatch");

    return APLRes_Success;
}

public void OnPluginStart()
{
    LoadTranslations("common.phrases");
    LoadTranslations("entWatch.phrases");

    HudInit();
    RestrictInit();
    TransferInit();
    SpawnInit();
    StripperInit();

    DatabaseConnect();
    DumpInit();
    ColorsInit();

    #if defined HALFZOMBIE
    HookEvent("player_spawn", OnPlayerSpawn);
    HookEvent("player_team", OnPlayerTeam);
    #endif

    HookEvent("player_death", OnPlayerDeath);
    HookEvent("player_disconnect", OnPlayerDisconnect);
    HookEvent("round_start", OnRoundStart, EventHookMode_PostNoCopy);
    HookEvent("round_end", OnRoundEnd, EventHookMode_PostNoCopy);

    (FindConVar("mp_restartgame")).AddChangeHook(OnRestartGame);

    #if defined ASSIST_USE
    AssistUseInit();
    #endif

    #if defined ADMIN_MENU
    AdminMenuInit();
    #endif

    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i))
        {
            OnClientPutInServer(i);
        }
    }
}

public void OnPluginEnd()
{
    ItemsOnPluginEnd();
    TransferOnPluginEnd();
}

public void OnMapStart()
{
    ConfigOnMapStart();
    ItemsOnMapStart();
    HudOnMapStart();

    #if defined HALFZOMBIE
	HalfZombieInit();
    #endif

    Late = false;
}

public void OnConfigsExecuted()
{
    #if defined HALFZOMBIE
	HalfZombieDeterminate();
    #endif
}

public void OnMapEnd()
{
    HudOnMapEnd();
    ConfigOnMapEnd();
}

#if defined HALFZOMBIE
public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    HalfZombieClientInit(client);
}

public void OnPlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    HalfZombieClientInit(client);
}
#endif
public void OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    ClientLostHandleAction(client, ACTION_DEATH);
}

public void OnPlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if(!client)
        return;
        
    ClientLostHandleAction(client, ACTION_DISCONNECT);
}

public void OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
    ItemsOnRoundStart();

    #if defined HALFZOMBIE
    HalfZombieInit();
    #endif
}

public void OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    TransferOnRoundEnd();
    ItemsOnRoundEnd();
}

public void OnEntitySpawned(int entity, const char[] classname)
{
    ItemsOnEntitySpawned(entity);
}

public void OnEntityDestroyed(int entity)
{
    ItemsOnEntityDestroyed(entity);
}

public void OnPlayerRunCmdPost(int client, int buttons)
{
    #if defined ASSIST_USE
    AssistUseOnPlayerRunCmdPost(client, buttons);
    #endif
}

public void OnRestartGame(ConVar cvar, const char[] oldValue, const char[] newValue)
{
    if(StringToInt(oldValue) == 0 && StringToInt(newValue) != -1)
        OnRoundEnd(null, "", false);
}