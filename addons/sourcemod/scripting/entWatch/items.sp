const int MAX_ITEMS = 200;

enum
{
    REGISTER_WEAPON,
    REGISTER_TRIGGER,
    REGISTER_BUTTON,
    REGISTER_COMPARE,
    REGISTER_RELAY
}

int Items_Count;
Item Items[MAX_ITEMS];

bool RoundStarted;

void ItemsOnMapStart()
{
    ItemsOnRoundStart();
}

void ItemsOnRoundStart()
{
    ItemsClear();
    RoundStarted = true;
    
    int entity = INVALID_ENT_REFERENCE;
    char classname[64];

    while((entity = FindEntityByClassname(entity, "*")) != -1)
    {
        if(GetEntityClassname(entity, classname, sizeof(classname)))
        {
            OnEntitySpawned(entity, classname);
        }
    }
}

void ItemsOnRoundEnd()
{
    RoundStarted = false;
    ItemsClear();
}

void ItemsOnPluginEnd()
{
    for(int i = 0; i < Items_Count; i++)
    {
        if(Items[i].Button)
        {
            SDKUnhook(Items[i].Button, SDKHook_Use, OnButtonPress);
            continue;
        }
        if(Items[i].Trigger)
        {
            SDKUnhook(Items[i].Trigger, SDKHook_StartTouch, OnTriggerTouch);
            SDKUnhook(Items[i].Trigger, SDKHook_EndTouch, OnTriggerTouch);
            SDKUnhook(Items[i].Trigger, SDKHook_Touch, OnTriggerTouch);
            continue;
        }
        if(Items[i].Compare)
        {
            UnhookSingleEntityOutput(Items[i].Compare, "OnEqualTo", Compare_OnEqualTo);
            continue;
        }
        if(Items[i].Relay)
        {
            UnhookSingleEntityOutput(Items[i].Relay, "OnTrigger", Relay_OnTrigger);
            continue;
        }

    }
}

void ItemsClear()
{
    if(!Items_Count)
        return;

    for(int i = 0; i < Items_Count; i++)
    {
		ItemClear(i);
    }
    Items_Count = 0;
}

void ItemsOnEntitySpawned(int entity)
{
    if(!RoundStarted)
        return;

    int hammerid = GetEntProp(entity, Prop_Data, "m_iHammerID");

    if(hammerid == 0)
        return;

    int config = -1;
    int type = -1;
    
    if(!ItemsRegisterGetKeyValues(hammerid, type, config))
        return;

    for(int i = 0; i < Items_Count; i++)
    {
        if(Items[i].Config != config)
            continue;

        if(ItemsRegisterItemEntity(i, Items[i], entity, type))
            return;
    }

    ItemsInitiateItem(entity, config, type);
}

bool ItemsRegisterGetKeyValues(int hammerid, int& type, int& config)
{
    for(int i = 0; i < Configs_Count; i++)
    {
        if(Configs[i].Weapon_HammerId == hammerid)
        {
            type = REGISTER_WEAPON;
            config = i;
            return true;
        }
        if(Configs[i].Trigger_HammerId == hammerid)
        {
            type = REGISTER_TRIGGER;
            config = i;
            return true;
        }
        if(Configs[i].Button_HammerId == hammerid)
        {
            type = REGISTER_BUTTON;
            config = i;
            return true;
        }
        if(Configs[i].Compare_HammerId == hammerid)
        {
            type = REGISTER_COMPARE;
            config = i;
            return true;
        }
        if(Configs[i].Relay_HammerId == hammerid)
        {
            type = REGISTER_RELAY;
            config = i;
            return true;
        }
    }

    return false;
}

bool ItemsRegisterItemEntity(int id, Item item, int entity, int type)
{
    int owner = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
    int parent = GetEntPropEnt(entity, Prop_Data, "m_pParent");

    switch(type)
    {
        case REGISTER_WEAPON:
        {
            if(item.Weapon)
                return false;

            if(owner != INVALID_ENT_REFERENCE)
            {
                if(!Late)
                    return false;

                item.Owner = owner;
            }

            item.Weapon = entity;
            ItemProcessCheckButton(id);
            return true;
        }
        case REGISTER_BUTTON:
        {
            if(item.Button)
                return false;

            if(item.Weapon && parent != INVALID_ENT_REFERENCE)
            {
                if(parent != item.Weapon && !AreEntitiesRelated(parent, item.Weapon))
                    return false;
            }

            SDKHook(entity, SDKHook_Use, OnButtonPress);
            item.Button = entity;
            return true;
        }
        case REGISTER_TRIGGER:
        {
            if(item.Trigger)
                return false;

            if(item.Weapon && parent != INVALID_ENT_REFERENCE)
            {
                if(parent != item.Weapon && !AreEntitiesRelated(parent, item.Weapon))
                    return false;
            }

            SDKHook(entity, SDKHook_StartTouch, OnTriggerTouch);
            SDKHook(entity, SDKHook_EndTouch, OnTriggerTouch);
            SDKHook(entity, SDKHook_Touch, OnTriggerTouch);
            item.Trigger = entity;
            return true;
        }
        case REGISTER_COMPARE:
        {
            if(item.Compare)
                return false;

            HookSingleEntityOutput(entity, "OnEqualTo", Compare_OnEqualTo);

            item.Compare = entity;
            return true;
        }
        case REGISTER_RELAY:
        {
            if(item.Relay)
                return false;

            HookSingleEntityOutput(entity, "OnTrigger", Relay_OnTrigger);

            item.Relay = entity;
            return true;
        }
    }

    return false;
}

void ItemsInitiateItem(int entity, int config, int type)
{
    if(Items_Count >= MAX_ITEMS)
        return;
    
    int item = Items_Count;
    ItemInit(item, config);
    ItemsRegisterItemEntity(item, Items[item], entity, type);
    Items_Count++;
}

void ItemProcessCheckButton(int item)
{
    if(Items[item].Button)
        return;

    CreateTimer(0.5, Timer_ItemFindButton, item);
}

public Action Timer_ItemFindButton(Handle timer, int item)
{
    if(!Items[item].Weapon || Items[item].Button || Items[item].Config == -1 || Configs[Items[item].Config].Mode == -1)
        return Plugin_Continue;

    int parent;
    int physbox;
    int door;
    int button;
    char classname[32];

    for(int i = MaxClients + 1; i < 2048; i++)
    {
        if(!IsValidEntity(i))
            continue;

        parent = GetEntPropEnt(i, Prop_Data, "m_pParent");

        if(parent != Items[item].Weapon)
            continue;

        if(Configs[Items[item].Config].Button_HammerId && Configs[Items[item].Config].Button_HammerId != GetEntProp(i, Prop_Data, "m_iHammerID"))
            continue;
        
        if(!GetEntityClassname(i, classname, sizeof(classname)))
            continue;

        if(StrContains(classname, "button", false) != -1){
            button = i; break;
        }
        else if(!strcmp(classname, "func_physbox_multiplayer", false))
            physbox = i;

        else if(StrContains(classname, "door", false) != -1)
            door = i;
    }

    int entity = ItemsGetButtonByPriority(button, physbox, door);

    if(entity)
        ItemsRegisterItemEntity(item, Items[item], entity, REGISTER_BUTTON);

    return Plugin_Continue;
}

// Возвращает кнопку по приоритету. Сначало func_button. Кнопка будет определена как айтем-кнопка.

int ItemsGetButtonByPriority(int button, int physbox, int door)
{
    if(button)  return button;
    if(physbox) return physbox;
    if(door)    return door;

    return 0;
}

void ItemsOnEntityDestroyed(int entity)
{
    for(int i = 0; i < Items_Count; i++)
    {
        if(Items[i].Weapon == entity)
        {
            ItemUnhook(i);
            ItemClear(i);
            ItemRemove(i);

            return;
        }
        if(Items[i].Trigger == entity)
        {
            Items[i].Trigger = 0;
            return;
        }
        if(Items[i].Button == entity)
        {
            SDKUnhook(Items[i].Button, SDKHook_Use, OnButtonPress);

            Items[i].RemovedButton = true;
            Items[i].Button = 0;
            return;
        }
        if(Items[i].Compare == entity)
        {
            Items[i].RemovedButton = true;
            Items[i].Compare = 0;
            return;
        }
        if(Items[i].Relay == entity)
        {
            Items[i].RemovedButton = true;
            Items[i].Relay = 0;
            return;
        }
    }
}

stock int ItemsGetByName(const char[] name)
{
    int len = strlen(name);
    for(int i = 0; i < Items_Count; i++)
    {
        if(strncmp(Configs[Items[i].Config].Name, name, len, false) == 0)
            return i;
    }

    return -1;
}

stock int ItemsGetByShortName(const char[] name)
{
    int len = strlen(name);
    for(int i = 0; i < Items_Count; i++)
    {
        if(strncmp(Configs[Items[i].Config].ShortName, name, len, false) == 0)
            return i;
    }

    return -1;
}

int ItemsGetByWeaponHammerID(int hammerid)
{
    for(int i = 0; i < Items_Count; i++)
    {
        if(Items[i].Config != -1 && Configs[Items[i].Config].Weapon_HammerId == hammerid)
            return i;
    }

    return -1;
}

int ItemsGetByWeapon(int weapon)
{
    for(int i = 0; i < Items_Count; i++)
    {
        if(Items[i].Weapon == weapon)
            return i;
    }

    return -1;
}

int ItemsGetByButton(int button)
{
    for(int i = 0; i < Items_Count; i++)
    {
        if(Items[i].Button == button)
            return i;
    }

    return -1;
}

int ItemsGetByCompare(int logic_compare)
{
    for(int i = 0; i < Items_Count; i++)
    {
        if(Items[i].Compare == logic_compare)
            return i;
    }

    return -1;
}

int ItemsGetByRelay(int logic_relay)
{
    for(int i = 0; i < Items_Count; i++)
    {
        if(Items[i].Relay == logic_relay)
            return i;
    }

    return -1;
}

stock int ItemFindClientItem(int client, int startitem = -1)
{
    for(int i = ++startitem; i < Items_Count; i++)
    {
        if(Items[i].Owner == client)
            return i;
    }

    return -1;
}

bool ItemDrop(int item)
{
    if(Configs[Items[item].Config].Slot == SLOT_NONE || Configs[Items[item].Config].Slot == SLOT_KNIFE)
        return false;

    SDKHooks_DropWeapon(Items[item].Owner, Items[item].Weapon, NULL_VECTOR, NULL_VECTOR);

    Items[item].Owner = 0;
    Items[item].Transfered = false;

    return true;
}

bool ItemIsReady(int item)
{
    float time = GetGameTime();

    switch(Configs[Items[item].Config].Mode)
    {
        case MODE_PROTECT:
        {
            return true;
        }
        case MODE_COOLDOWN:
        {
        	if (Items[item].Cooldown < time)
                return true;
        }
        case MODE_MAXUSES:
        {
        	if (Items[item].Uses < Configs[Items[item].Config].Maxuses)
                return true;
        }
        case MODE_MAXUSESCD:
        {
        	if (Items[item].Cooldown < time && Items[item].Uses < Configs[Items[item].Config].Maxuses)
                return true;
        }
        case MODE_CHARGESCD:
        {
        	if (Items[item].Cooldown < time)
                return true;
        }
        default:
        {
            return true;
        }
    }
    return false;
}

void ItemReload(int item)
{
    float time = GetGameTime();
    
    switch(Configs[Items[item].Config].Mode)
    {
        case MODE_COOLDOWN:
        {
            Items[item].Cooldown = time + Configs[Items[item].Config].Cooldown;
        }
        case MODE_MAXUSES:
        {
            Items[item].Uses++;
        }
        case MODE_MAXUSESCD:
        {
            Items[item].Cooldown = time + Configs[Items[item].Config].Cooldown;
            Items[item].Uses++;
        }
        case MODE_CHARGESCD:
        {
            Items[item].Uses++;
            
            if (Items[item].Uses >= Configs[Items[item].Config].Maxuses)
            {
                Items[item].Cooldown = time + Configs[Items[item].Config].Cooldown;
                Items[item].Uses = 0;
            
            }
        }
    }
}

stock void ItemFormat(int item, char[] finalBuffer, int maxlength)
{
    if(Items[item].RemovedButton)
    {
        FormatEx(finalBuffer, maxlength, "%s[D]: %N\n", Configs[Items[item].Config].ShortName, Items[item].Owner);
        return;
    }
    float cd = Items[item].Cooldown - GetGameTime();
    int id = Items[item].Config;
    static char buffer[16];
    switch(Configs[id].Mode)
    {
    	case MODE_COOLDOWN:
    	{
    		if (cd > 0.0)
    		{
    			FormatEx(buffer, sizeof(buffer), "[%i]", RoundToCeil(cd));
    		}
    		else
    		{
    			FormatEx(buffer, sizeof(buffer), "[%s]", "R");
    		}
    	}
    	case MODE_MAXUSES:
    	{
    		if (Items[item].Uses < Configs[id].Maxuses)
    		{
    			FormatEx(buffer, sizeof(buffer), "[%i/%i]", Items[item].Uses, Configs[id].Maxuses);
    		}
    		else
    		{
    			FormatEx(buffer, sizeof(buffer), "[%s]", "D");
    		}
    	}
    	case MODE_MAXUSESCD:
    	{
    		if (cd > 0.0)
    		{
    			FormatEx(buffer, sizeof(buffer), "[%i]", RoundToCeil(cd));
    		}
    		else
    		{
    			if (Items[item].Uses < Configs[id].Maxuses)
    			{
    				FormatEx(buffer, sizeof(buffer), "[%i/%i]", Items[item].Uses, Configs[id].Maxuses);
    			}
    			else
    			{
    				FormatEx(buffer, sizeof(buffer), "[%s]", "D");
    			}
    		}
    	}
    	case MODE_CHARGESCD:
    	{
    		if (cd > 0.0)
    		{
    			FormatEx(buffer, sizeof(buffer), "[%i]", RoundToCeil(cd));
    		}
    		else
    		{
    			FormatEx(buffer, sizeof(buffer), "[%i/%i]", Items[item].Uses, Configs[id].Maxuses);
    		}
    	}
    	default:
    	{
    		FormatEx(buffer, sizeof(buffer), "[%s]", "N/A");
    	}
    }

    FormatEx(finalBuffer, maxlength, "%s%s: %N\n", Configs[id].ShortName, buffer, Items[item].Owner);
}

void ItemRemove(int item)
{
    for(int i = item; i < Items_Count; i++)
    {
        Items[i] = Items[i + 1];
    }
    Items_Count--;
}


void ItemInit(int item, int config)
{
    ItemClear(item);
    Items[item].Config = config;
}

void ItemClear(int item)
{
    Items[item].Config = -1;
    Items[item].Weapon = 0;
    Items[item].Button = 0;
    Items[item].Trigger = 0;
    Items[item].Compare = 0;
    Items[item].Relay = 0;
    Items[item].Owner = 0;
    Items[item].Uses = 0;
    Items[item].Cooldown = 0.0;
    Items[item].Transfered = false;
    Items[item].RemovedButton = false;
}

void ItemUnhook(int item)
{
    if(Items[item].Button)
    {
        SDKUnhook(Items[item].Button, SDKHook_Use, OnButtonPress);
    }
    if(Items[item].Trigger)
    {
        SDKUnhook(Items[item].Trigger, SDKHook_StartTouch, OnTriggerTouch);
        SDKUnhook(Items[item].Trigger, SDKHook_EndTouch, OnTriggerTouch);
        SDKUnhook(Items[item].Trigger, SDKHook_Touch, OnTriggerTouch);
    }
    if(Items[item].Compare)
    {
        UnhookSingleEntityOutput(Items[item].Compare, "OnEqualTo", Compare_OnEqualTo);
    }
    if(Items[item].Relay)
    {
        UnhookSingleEntityOutput(Items[item].Relay, "OnTrigger", Relay_OnTrigger);
    }
}