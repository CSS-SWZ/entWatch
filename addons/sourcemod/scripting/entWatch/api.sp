GlobalForward g_OnConfigLoaded;
GlobalForward g_OnDatabaseLoaded;
GlobalForward g_OnClientLoaded;
GlobalForward g_OnClientItemUse;
GlobalForward g_OnClientItemDrop;
GlobalForward g_OnClientItemPickup;

void APIInit()
{
    g_OnConfigLoaded = new GlobalForward("entWatch_OnConfigLoaded", ET_Ignore);
    g_OnDatabaseLoaded = new GlobalForward("entWatch_OnDatabaseLoaded", ET_Ignore);
    g_OnClientLoaded = new GlobalForward("entWatch_OnClientLoaded", ET_Ignore, Param_Cell);
    g_OnClientItemUse = new GlobalForward("entWatch_OnClientItemUse", ET_Ignore, Param_Cell, Param_Cell);
    g_OnClientItemDrop = new GlobalForward("entWatch_OnClientItemDrop", ET_Ignore, Param_Cell, Param_Cell);
    g_OnClientItemPickup = new GlobalForward("entWatch_OnClientItemPickup", ET_Ignore, Param_Cell, Param_Cell);

    CreateNative("entWatch_IsConfigLoaded", Native_IsConfigLoaded);
    CreateNative("entWatch_IsDatabaseLoaded", Native_IsDatabaseLoaded);
    CreateNative("entWatch_IsClientLoaded", Native_IsClientLoaded);
    CreateNative("entWatch_GetConfigsCount", Native_GetConfigsCount);
    CreateNative("entWatch_GetItemsCount", Native_GetItemsCount);
    CreateNative("entWatch_GetConfig", Native_GetConfig);
    CreateNative("entWatch_GetItem", Native_GetItem);

    CreateNative("entWatch_ClientHasItem", Native_ClientHasItem);
}

void APIOnConfigLoaded()
{
    Call_StartForward(g_OnConfigLoaded);
    Call_Finish();
}

void APIOnDatabaseLoaded()
{
    Call_StartForward(g_OnDatabaseLoaded);
    Call_Finish();
}

void APIOnClientLoaded(int client)
{
    Call_StartForward(g_OnClientLoaded);
    Call_PushCell(client);
    Call_Finish();
}

void APIOnClientItemUse(int client, int item)
{
    Call_StartForward(g_OnClientItemUse);
    Call_PushCell(client);
    Call_PushCell(item);
    Call_Finish();
}

void APIOnClientItemDrop(int client, int item)
{
    Call_StartForward(g_OnClientItemDrop);
    Call_PushCell(client);
    Call_PushCell(item);
    Call_Finish();
}

void APIOnClientItemPickup(int client, int item)
{
    Call_StartForward(g_OnClientItemPickup);
    Call_PushCell(client);
    Call_PushCell(item);
    Call_Finish();
}

public any Native_IsConfigLoaded(Handle plugin, int numParams)
{
    return (Configs_Count > 0);
}

public any Native_IsDatabaseLoaded(Handle plugin, int numParams)
{
    return DBLoaded;
}

public any Native_IsClientLoaded(Handle plugin, int numParams)
{
    return Clients[GetNativeCell(1)].Authorized;
}

public int Native_GetConfigsCount(Handle plugin, int numParams)
{
    return Configs_Count;
}

public int Native_GetItemsCount(Handle plugin, int numParams)
{
    return Items_Count;
}

public any Native_GetConfig(Handle plugin, int numParams)
{
    int config = GetNativeCell(1);
    int size = GetNativeCell(3);

    if (size != sizeof(Config))
    {
        ThrowNativeError(200, "Config does not match latest(got %i expected %i). Please update your includes and recompile your plugins", size, sizeof(Config));
        return false;
    }

    return (SetNativeArray(2, Configs[config], size) == SP_ERROR_NONE);
}

public any Native_GetItem(Handle plugin, int numParams)
{
    int item = GetNativeCell(1);
    int size = GetNativeCell(3);

    if (size != sizeof(Item))
    {
        ThrowNativeError(200, "Item does not match latest(got %i expected %i). Please update your includes and recompile your plugins", size, sizeof(Item));
        return false;
    }

    return (SetNativeArray(2, Items[item], size) == SP_ERROR_NONE);
}

public int Native_ClientHasItem(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);

    if(ItemFindClientItem(client) != -1)
        return 1;

    return 0;
}