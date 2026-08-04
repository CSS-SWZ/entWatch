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

// Пост-форвард, а не ZR_OnClientInfect: в pre-форварде класс игрока ещё
// прежний, для mother-зомби ZR подменяет его уже после нас. Здесь класс
// окончательный, и HalfZombie[] совпадает с тем, кем игрок стал на самом деле.
public void ZR_OnClientInfected(int client, int attacker, bool motherInfect, bool respawnOverride, bool respawn)
{
    HalfZombieDeterminateClient(client);
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

	if (StrContains(buffer, "halfzombie", false) != -1 || StrContains(buffer, "old", false) != -1)
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