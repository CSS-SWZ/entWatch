// Sg
stock void StringToLowercase(char[] text)
{
	int length = strlen(text);
	for(int i = 0; i < length; ++i)
	{
		if(IsCharUpper(text[i]))
		{
			text[i] = CharToLower(text[i]);
		}
	}
}