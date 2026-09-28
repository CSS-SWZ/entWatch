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

    // Пустая строка не должна совпадать ни с чем: strncmp() с нулевой длиной
    // возвращает 0 и вернул бы первый попавшийся предмет.
    if(len == 0)
        return -1;

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

// Устойчивый ключ предмета для меню и прочего кода, живущего между кадрами:
// индексы в Items[] сдвигаются при ItemRemove(), а ссылка на оружие - нет.
int ItemGetRef(int item)
{
    return EntIndexToEntRef(Items[item].Weapon);
}

// Обратное преобразование. -1, если предмета больше нет: сущность оружия
// удалена (ссылка протухла) либо предмет снят с учёта.
int ItemsGetByRef(int ref)
{
    int weapon = EntRefToEntIndex(ref);

    if(weapon == INVALID_ENT_REFERENCE)
        return -1;

    return ItemsGetByWeapon(weapon);
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

