void RestrictOnLibraryAdded(const char[] name)
{
    #pragma unused name
}

void RestrictOnLibraryRemoved(const char[] name)
{
    #pragma unused name
}

void RestrictOnAllPluginsLoaded()
{
}

// Без системы рестриктов команды и хранилище не нужны.
void RestrictInit()
{
}

// Как при недоступной базе: игрок авторизован, форвард загрузки не отправляется.
void RestrictOnClientAuth(int client)
{
    Clients[client].Authorized = true;
}

// Реализация не хранит состояние слота.
void RestrictOnClientDisconnect(int client)
{
    #pragma unused client
}

// Реализация не хранит временные рестрикты карты.
void RestrictOnMapEnd()
{
}

// Эта реализация никого не ограничивает: рестрикты отключены.
bool RestrictClientHasRestrict(int client)
{
    #pragma unused client
    return false;
}

// Натив остаётся доступен, но хранилища в этой сборке нет.
bool RestrictIsDatabaseLoaded()
{
    return false;
}
