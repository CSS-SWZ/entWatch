// Контракт подсистемы рестриктов. Каждая реализация определяет все функции ниже.
// RestrictInit — OnPluginStart: регистрация команд и подключение к хранилищу.
// RestrictOnAllPluginsLoaded — OnAllPluginsLoaded: зависимости от других плагинов.
// RestrictOnLibraryAdded / RestrictOnLibraryRemoved — OnLibraryAdded / OnLibraryRemoved.
// RestrictOnClientAuth — ClientAuth: выставить Authorized; после загрузки вызвать APIOnClientLoaded.
// RestrictOnClientDisconnect — OnClientDisconnect: сбросить состояние слота.
// RestrictOnMapEnd — OnMapEnd: сбросить состояние, живущее до смены карты.
// RestrictClientHasRestrict — игровые хуки и меню: проверка без запросов и проходов по спискам.
// RestrictIsDatabaseLoaded — Native_IsDatabaseLoaded: готово ли хранилище.

#if defined RESTRICT_BUILTIN && defined RESTRICT_CORE
	#error "RESTRICT_BUILTIN and RESTRICT_CORE are mutually exclusive (modules.sp)"
#endif

#if defined RESTRICT_BUILTIN
	#include "restrict/builtin.sp"
#elseif defined RESTRICT_CORE
	#include "restrict/core.sp"
#else
	#include "restrict/none.sp"
#endif
