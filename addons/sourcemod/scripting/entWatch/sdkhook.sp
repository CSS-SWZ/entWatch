public Action OnWeaponTouch(int client, int weapon)
{
    static int item;
    item = ItemsGetByWeapon(weapon);

    if(item == -1)
        return Plugin_Continue;

    if(!Clients[client].Authorized)
        return Plugin_Handled;

    if(RestrictClientHasRestrict(client))
        return Plugin_Handled;

    #if defined HALFZOMBIE
    if(HalfZombie[client])
        return Plugin_Handled;
    #endif

    return Plugin_Continue;
}

public void OnWeaponPickup(int client, int weapon)
{
    int item = ItemsGetByWeapon(weapon);

    if(item == -1)
        return;

    Items[item].Owner = client;
    PrintToChatItemAction(item, ACTION_PICK);

    APIOnClientItemPickup(client, item);
}

public void OnWeaponDrop(int client, int weapon)
{
    int item = ItemsGetByWeapon(weapon);

    if(item == -1)
        return;

    Items[item].Transfered = false;

    PrintToChatItemAction(item, ACTION_DROP);
    Items[item].Owner = 0;

    APIOnClientItemDrop(client, item);
}

public Action OnButtonPress(int button, int activator, int caller, UseType type, float value)
{
    if(!RoundStarted)
        return Plugin_Handled;

    if(activator <= 0 || activator > MaxClients)
        return Plugin_Continue;

    int item = ItemsGetByButton(button);

    if(item == -1)
        return Plugin_Continue;
        
    if(Items[item].Owner != activator)
        return Plugin_Handled;

    if(RestrictClientHasRestrict(activator))
        return Plugin_Handled;

    if(!Items[item].Compare && !Items[item].Relay && !ItemIsReady(item))
        return Plugin_Handled;

    if(Configs[Items[item].Config].Filter[0])
        DispatchKeyValue(Items[item].Owner, "targetname", Configs[Items[item].Config].Filter);
    
    if(Items[item].Compare || Items[item].Relay)
        return Plugin_Continue;

    APIOnClientItemUse(activator, item);
    
    ItemReload(item);
    PrintToChatItemAction(item, ACTION_USE);
    return Plugin_Continue;
}

public void Compare_OnEqualTo(const char[] output, int logic_compare, int activator, float delay)
{
    if(!RoundStarted || activator <= 0 || activator > MaxClients)
        return;
    
    int item = ItemsGetByCompare(logic_compare);
    
    if(!Items[item].Owner)
        return;

    APIOnClientItemUse(activator, item);

    ItemReload(item);
    PrintToChatItemAction(item, ACTION_USE);
}

public void Relay_OnTrigger(const char[] output, int logic_relay, int activator, float delay)
{
    if(!RoundStarted || activator <= 0 || activator > MaxClients)
        return;

    int item = ItemsGetByRelay(logic_relay);

    if(!Items[item].Owner)
        return;

    APIOnClientItemUse(activator, item);
    
    ItemReload(item);
    PrintToChatItemAction(item, ACTION_USE);
}

public Action OnTriggerTouch(int entity, int activator)
{
    if(!RoundStarted)
        return Plugin_Handled;

    if(activator <= 0 || activator > MaxClients)
        return Plugin_Continue;

    if(RestrictClientHasRestrict(activator))
        return Plugin_Handled;

    #if defined HALFZOMBIE
    if(HalfZombie[activator])
        return Plugin_Handled;
    #endif

    return Plugin_Continue;
}