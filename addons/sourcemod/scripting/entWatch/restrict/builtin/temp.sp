// Временные рестрикты - до ближайшей смены карты. Живут только в памяти и в базу
// не попадают, поэтому работают и тогда, когда база недоступна: обычные рестрикты
// в этом случае выключены целиком (fail-open), и восстановить порядок было бы
// нечем. Ключ - аккаунт, а не слот, так что перезаход игрока рестрикт не снимает.
// Сам список читается только при подключении, выдаче и снятии; горячий путь
// смотрит в Restricts[].Temporary.
#define MAX_TEMP_RESTRICTS 100

int TempRestricts[MAX_TEMP_RESTRICTS];
int TempRestricts_Count;

// Пересевает кэш из списка. Зовётся из ClientAuth, как только становится известен
// аккаунт: это единственный момент, когда игрок мог получить временный рестрикт
// до своего подключения - выдали, он вышел и вернулся.
void RestrictClientInitTemp(int client)
{
	Restricts[client].Temporary = RestrictHasTempRestrict(Clients[client].Account);
}

// Сброс привязан к концу карты, а не к началу, намеренно. Кнопка Reload в
// sm_eadmin вызывает OnMapStart() руками, чтобы перечитать конфиги предметов, и
// на старте здесь она стирала бы заодно все временные рестрикты - молча, посреди
// карты. OnMapEnd она не вызывает, а настоящая смена карты вызывает всегда.
void RestrictOnMapEnd()
{
	TempRestricts_Count = 0;

	// Список опустел - опустошаем и кэш. На смене карты OnClientDisconnect
	// приходит на всех, и Clear() сбросил бы флаги сам, но полагаться на порядок
	// этих двух событий не нужно: здесь дешевле пройти по слотам явно.
	for(int i = 1; i <= MaxClients; i++)
	{
		Restricts[i].Temporary = false;
	}
}

int RestrictFindTempRestrict(int account)
{
	for(int i = 0; i < TempRestricts_Count; i++)
	{
		if(TempRestricts[i] == account)
			return i;
	}

	return -1;
}

bool RestrictHasTempRestrict(int account)
{
	return (RestrictFindTempRestrict(account) != -1);
}

// false - список переполнен. Молча терять рестрикт нельзя, поэтому решение
// принимает вызывающий: он и сообщает админу, и пишет в лог.
bool RestrictAddTempRestrict(int account)
{
	if(TempRestricts_Count >= MAX_TEMP_RESTRICTS)
		return false;

	TempRestricts[TempRestricts_Count] = account;
	TempRestricts_Count++;

	return true;
}

void RestrictRemoveTempRestrict(int account)
{
	int index = RestrictFindTempRestrict(account);

	if(index == -1)
		return;

	// Порядок в списке не значим, поэтому дырку затыкаем последним элементом,
	// а не сдвигаем хвост.
	TempRestricts_Count--;
	TempRestricts[index] = TempRestricts[TempRestricts_Count];
}

