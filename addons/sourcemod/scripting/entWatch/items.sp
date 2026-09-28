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

#include "items/register.sp"
#include "items/search.sp"
#include "items/state.sp"

void ItemsOnMapStart()
{
    // Поздней загрузке сканирование нужно: round_start для неё уже прошёл.
    if(Late)
    {
        ItemsOnRoundStart();
        return;
    }

    // На обычной смене карты сканировать нечего: round_start ещё не было, а
    // сущности карты после него будут пересозданы. Раннее сканирование
    // выставляло RoundStarted = true, после чего OnEntitySpawned вешал
    // SDKHook_Use первый раз, а round_start - второй: ItemsClear() стирает
    // учёт, но не снимает хуки, и одно нажатие считалось за два использования.
    // Учёт прошлой карты при этом обязан уйти именно здесь: round_end перед
    // сменой карты случается не всегда, а Items[].Config после ConfigOnMapStart()
    // указывает уже в конфиги новой карты.
    ItemsClear();
    RoundStarted = false;
}

void ItemsOnRoundStart()
{
    ItemsClear();
    RoundStarted = true;
    
    int entity = INVALID_ENT_REFERENCE;

    while((entity = FindEntityByClassname(entity, "*")) != -1)
        ItemsOnEntitySpawned(entity);
}

void ItemsOnRoundEnd()
{
    RoundStarted = false;
    ItemsClear();
}

void ItemsOnPluginEnd()
{
    // У предмета может быть сразу и кнопка, и триггер, и compare, и relay,
    // поэтому снимаем всё разом - ItemUnhook() проверяет каждое поле само.
    for(int i = 0; i < Items_Count; i++)
    {
        ItemUnhook(i);
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

void ItemRemove(int item)
{
    for(int i = item; i < Items_Count - 1; i++)
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
    Items[item].Wait = 0.0;
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

stock void RemoveItemByConfig(int config)
{
	int i = 0;

	while(i < Items_Count)
	{
		if(Items[i].Config == config)
		{
			// Слот нужно освободить целиком: снять хуки с ещё живых кнопки,
			// триггера, compare и relay, иначе они продолжат срабатывать на
			// предмет, которого больше нет.
			ItemUnhook(i);
			ItemClear(i);
			ItemRemove(i);

			// ItemRemove() сдвинул массив вниз - на этом же индексе теперь
			// стоит следующий предмет, поэтому i не увеличиваем.
			continue;
		}

		if(Items[i].Config > config)
		{
			Items[i].Config--;
		}

		i++;
	}
}

