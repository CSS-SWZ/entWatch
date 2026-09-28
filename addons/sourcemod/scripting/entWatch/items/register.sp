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

    // В таймер уходит ссылка на оружие, а не индекс. За эти 0.5 с ItemRemove()
    // сдвигает Items[], и сохранённый индекс начинает значить другой предмет:
    // кнопка регистрировалась в чужой слот, а живой предмет оставался с
    // Button == 0, то есть ItemsGetByButton() не находил его и OnButtonPress()
    // пропускал нажатие вообще без проверки владельца.
    CreateTimer(0.5, Timer_ItemFindButton, ItemGetRef(item), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ItemFindButton(Handle timer, int ref)
{
    int item = ItemsGetByRef(ref);

    if(item == -1)
        return Plugin_Continue;

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

int ItemsGetButtonByPriority(int button, int physbox, int door)
{
    if(button)  return button;
    if(physbox) return physbox;
    if(door)    return door;

    return 0;
}

bool AreEntitiesRelated(int child, int owner)
{
	int parent = GetEntPropEnt(child, Prop_Data, "m_pParent");
	
	if(parent == INVALID_ENT_REFERENCE)
		return false;
	
	if(parent == owner)
		return true;
		
	return AreEntitiesRelated(parent, owner);
}

