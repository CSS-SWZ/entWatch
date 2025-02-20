#if !defined HALFZOMBIE
    #warning "Halfzombie module: not included"
	#endinput
#endif

#undef REQUIRE_PLUGIN
#tryinclude <zombiereloaded>
#define REEQUIRE_PLUGIN

bool HalfZombieEnabled;
bool HalfZombie[MAXPLAYERS + 1];

void HalfZombieInit()
{
    for(int i = 1; i <= MaxClients; ++i)
        HalfZombieClientInit(i);
}

void HalfZombieClientInit(int client)
{
    HalfZombie[client] = false;
}

#if defined _zr_included
public void ZR_OnClientHumanPost(int client, bool respawn, bool protect)
{
    HalfZombieClientInit(client);
}

public Action ZR_OnClientInfect(int &client, int &attacker, bool &motherInfect, bool &respawnOverride, bool &respawn)
{
    HalfZombieDeterminateClient(client);

    return Plugin_Continue;
}
#endif

#if defined _zr_included
void HalfZombieDeterminate()
{
	HalfZombieEnabled = false;

	ConVar cvar = FindConVar("zr_config_path_playerclasses");

	if (!cvar)
		return;

	char buffer[PLATFORM_MAX_PATH];
	cvar.GetString(buffer, sizeof(buffer));

	if (StrContains(buffer, "halfzombie", false) != -1)
		HalfZombieEnabled = true;
}

void HalfZombieDeterminateClient(int client)
{
    if (!HalfZombieEnabled)
    	return;
    
    HalfZombie[client] = false;

    int zombieClass = ZR_GetZombieClass(client);
    
    char buffer[PLATFORM_MAX_PATH];
    ZR_GetClassDisplayName(zombieClass, buffer, sizeof(buffer), 1);
    
    if (StrContains(buffer, "frazzle", false) != -1)
        HalfZombie[client] = true;
}
#endif