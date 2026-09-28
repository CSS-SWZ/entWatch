// Рестрикты из ядра RestrictCore. Ядро необязательно: без него, а также пока оно не
// знает данных игрока, игрок считается неограниченным - как у встроенной системы при
// недоступной базе.
#undef REQUIRE_PLUGIN
#include <RestrictCore>
#define REQUIRE_PLUGIN

#define RESTRICT_TYPE "entwatch.pickup"

// Загружено ли ядро. Нативы ядра необязательные: без него их вызов - ошибка.
static bool RestrictCore;
static bool restricted[MAXPLAYERS + 1];

void RestrictOnLibraryAdded(const char[] name)
{
	if (strcmp(name, "RestrictCore") == 0)
	{
		RestrictCore = true;
	}
}

// Ядро выгрузили: ограничения больше не известны, все считаются неограниченными.
// После повторной загрузки ядро само пришлёт RCOnClientReady игрокам в игре.
void RestrictOnLibraryRemoved(const char[] name)
{
	if (strcmp(name, "RestrictCore") != 0)
		return;

	RestrictCore = false;

	for (int client = 1; client <= MaxClients; client++)
	{
		restricted[client] = false;
	}
}

void RestrictOnAllPluginsLoaded()
{
	RestrictInit();
}

// Команд и хранилища у этой реализации нет. Зовётся из OnPluginStart и повторно из
// OnAllPluginsLoaded: на старте сервера ядро может загрузиться позже entWatch.
void RestrictInit()
{
	RestrictCore = LibraryExists("RestrictCore");

	if (!RestrictCore)
		return;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientConnected(client))
		{
			RestrictCoreReadClient(client);
		}
	}
}

// Авторизуем сразу, не дожидаясь RCOnClientReady: без ядра или без его базы форвард
// не придёт, и игрок не смог бы поднять ни одного предмета. Если данные уже
// загружены (смена карты, кэш ядра), ограничение действует с первого же тика.
void RestrictOnClientAuth(int client)
{
	RestrictCoreReadClient(client);

	Clients[client].Authorized = true;
	APIOnClientLoaded(client);
}

void RestrictOnClientDisconnect(int client)
{
	restricted[client] = false;
}

// Ограничения ядра переживают смену карты и хранятся в нём самом.
void RestrictOnMapEnd()
{
}

bool RestrictClientHasRestrict(int client)
{
	return restricted[client];
}

// Своей базы нет. Хранилище - ядро: пока оно загружено, отвечаем "готово".
bool RestrictIsDatabaseLoaded()
{
	return RestrictCore;
}

// RC_IsRestricted отвечает, как только ядро загрузило данные, в том числе до
// RCOnClientReady; до загрузки - false.
static void RestrictCoreReadClient(int client)
{
	if (!RestrictCore || !RC_IsClientLoaded(client))
		return;

	restricted[client] = RC_IsRestricted(client, RESTRICT_TYPE);
}

public void RCOnClientReady(int client)
{
	restricted[client] = RC_IsRestricted(client, RESTRICT_TYPE);
}

public void RCOnRestrictChanged(int client, const char[] type, bool is_restricted)
{
	if (strcmp(type, RESTRICT_TYPE) == 0)
	{
		restricted[client] = is_restricted;
	}
}
