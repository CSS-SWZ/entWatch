// Контракт подсистемы рестриктов. Каждая реализация определяет все функции ниже.
// RestrictInit — OnPluginStart: регистрация команд и подключение к хранилищу.
// RestrictOnClientAuth — ClientAuth: выставить Authorized; после загрузки вызвать APIOnClientLoaded.
// RestrictOnClientDisconnect — OnClientDisconnect: сбросить состояние слота.
// RestrictOnMapEnd — OnMapEnd: сбросить состояние, живущее до смены карты.
// RestrictClientHasRestrict — игровые хуки и меню: проверка без запросов и проходов по спискам.
// RestrictIsDatabaseLoaded — Native_IsDatabaseLoaded: готово ли хранилище.

#if defined RESTRICT_BUILTIN
	#include "restrict/builtin.sp"
#else
	#include "restrict/none.sp"
#endif
