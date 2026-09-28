// Снимает владельца с предмета. Отделено от ItemDrop() намеренно: "оружие нельзя
// бросить на землю" (ножи, I5) и "владелец больше не владеет" - разные вещи.
// У предмета не может быть мёртвого или вышедшего владельца.
void ItemReleaseOwner(int item)
{
    int owner = Items[item].Owner;

    if(owner == 0)
        return;

    Items[item].Owner = 0;
    Items[item].Transfered = false;

    // bypassHooks у SDKHooks_DropWeapon() по умолчанию true (sdkhooks.inc:452),
    // поэтому OnWeaponDrop() на программном пути не срабатывает и форвард
    // сторонним плагинам надо отправить самим.
    APIOnClientItemDrop(owner, item);
}

bool ItemDrop(int item)
{
    if(Configs[Items[item].Config].Slot == SLOT_NONE || Configs[Items[item].Config].Slot == SLOT_KNIFE)
        return false;

    SDKHooks_DropWeapon(Items[item].Owner, Items[item].Weapon, NULL_VECTOR, NULL_VECTOR);
    ItemReleaseOwner(item);

    return true;
}

bool ItemIsReady(int item)
{
    float time = GetGameTime();

    if(Items[item].Wait >= time)
        return false;

    if (HasEntProp(Items[item].Button, Prop_Data, "m_bLocked") && GetEntProp(Items[item].Button, Prop_Data, "m_bLocked"))
        return false;

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

    // Fix ghost using
    time += GetTickInterval() * 5.0;

    if (HasEntProp(Items[item].Button, Prop_Data, "m_flWait"))
	{
        float wait = GetEntPropFloat(Items[item].Button, Prop_Data, "m_flWait");

        if(wait > 0.0)
            Items[item].Wait = time + wait;
	}
    
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

