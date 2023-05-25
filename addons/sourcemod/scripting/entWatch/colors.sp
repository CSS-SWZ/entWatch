enum
{
    COLOR_TAG,
    COLOR_NAME,
    COLOR_OTHER,
	COLOR_ITEM,
    COLOR_TOTAL
}

char Colors[COLOR_TOTAL][32];

void ColorsInit()
{
	char buffer[256];
	
	KeyValues hKeyValues = new KeyValues("Colors");
	BuildPath(Path_SM, buffer, 256, "configs/entwatch/colors.cfg");
	
	if(!hKeyValues.ImportFromFile(buffer))
	{
		SetFailState("Confilg file \"%s\" not founded.", buffer);
	}
	
	hKeyValues.GetString("tagcolor", Colors[COLOR_TAG], 32);
	hKeyValues.GetString("nickcolor", Colors[COLOR_NAME], 32);
	hKeyValues.GetString("othercolor", Colors[COLOR_OTHER], 32);
	hKeyValues.GetString("itemcolor", Colors[COLOR_ITEM], 32);
	
	delete hKeyValues;
}