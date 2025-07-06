#if defined _entWatch_included
	#endinput
#endif

#define _entWatch_included

#include "entWatch/Config.inc"
#include "entWatch/Item.inc"

public SharedPlugin __pl_entWatch =
{
	name = "entWatch",
	file = "entWatch.smx",

	#if defined REQUIRE_PLUGIN
		required = 1
	#else
		required = 0
	#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_entWatch_SetNTVOptional()
{
	MarkNativeAsOptional("entWatch_IsConfigLoaded");
	MarkNativeAsOptional("entWatch_IsDatabaseLoaded");
	MarkNativeAsOptional("entWatch_IsClientLoaded");
	MarkNativeAsOptional("entWatch_GetConfigsCount");
	MarkNativeAsOptional("entWatch_GetItemsCount");
	MarkNativeAsOptional("entWatch_GetConfig");
	MarkNativeAsOptional("entWatch_GetItem");
	MarkNativeAsOptional("entWatch_ClientHasItem");
}
#endif

native bool entWatch_IsConfigLoaded();
native bool entWatch_IsDatabaseLoaded();
native bool entWatch_IsClientLoaded(int client);
native int entWatch_GetConfigsCount();
native int entWatch_GetItemsCount();

native bool entWatch_GetConfig(int config, any[] cache, int size = sizeof(Config));
native bool entWatch_GetItem(int item, any[] cache, int size = sizeof(Item));

native bool entWatch_ClientHasItem(int client);

forward void entWatch_OnConfigLoaded();
forward void entWatch_OnDatabaseLoaded();
forward void entWatch_OnClientLoaded(int client);
forward void entWatch_OnClientItemUse(int client, int item);
forward void entWatch_OnClientItemDrop(int client, int item);
forward void entWatch_OnClientItemPickup(int client, int item);
