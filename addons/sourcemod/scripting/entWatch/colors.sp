enum
{
    COLOR_TAG,
    COLOR_NAME,
    COLOR_OTHER,
	COLOR_ITEM,
    COLOR_TOTAL
}

char Colors[COLOR_TOTAL][32];

StringMap ColorsMap;

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

	InitColorsMap();
}

void ColorNameToColorCode(char[] color, int size)
{
	int symbol = FindCharInString(color, '{');
	int symbol2 = FindCharInString(color, '}', true);

	if(symbol == -1 || symbol2 == -1 || symbol2 < 3 || symbol2 <= symbol)
		return;

	color[symbol2] = 0;
	
	char colorcode[16];
	if(ColorsMap.GetString(color[symbol + 1], colorcode, sizeof(colorcode)))
	{
		strcopy(color, size, colorcode);
	}
	else
	{
		FormatEx(color, size, "#%s", Colors[COLOR_ITEM]);
	}
}

void InitColorsMap()
{
	delete ColorsMap;
	ColorsMap = new StringMap();

	ColorsMap.SetString("aliceblue", "#F0F8FF");
	ColorsMap.SetString("allies", "#4D7942"); // same as Allies team in DoD:S
	ColorsMap.SetString("ancient", "#EB4B4B"); // same as Ancient item rarity in Dota 2
	ColorsMap.SetString("antiquewhite", "#FAEBD7");
	ColorsMap.SetString("aqua", "#00FFFF");
	ColorsMap.SetString("aquamarine", "#7FFFD4");
	ColorsMap.SetString("arcana", "#ADE55C"); // same as Arcana item rarity in Dota 2
	ColorsMap.SetString("axis", "#FF4040"); // same as Axis team in DoD:S
	ColorsMap.SetString("azure", "#007FFF");
	ColorsMap.SetString("beige", "#F5F5DC");
	ColorsMap.SetString("bisque", "#FFE4C4");
	ColorsMap.SetString("black", "#000000");
	ColorsMap.SetString("blanchedalmond", "#FFEBCD");
	ColorsMap.SetString("blue", "#99CCFF"); // same as BLU/Counter-Terrorist team color
	ColorsMap.SetString("blueviolet", "#8A2BE2");
	ColorsMap.SetString("brown", "#A52A2A");
	ColorsMap.SetString("burlywood", "#DEB887");
	ColorsMap.SetString("cadetblue", "#5F9EA0");
	ColorsMap.SetString("chartreuse", "#7FFF00");
	ColorsMap.SetString("chocolate", "#D2691E");
	ColorsMap.SetString("collectors", "#AA0000"); // same as Collector's item quality in TF2
	ColorsMap.SetString("common", "#B0C3D9"); // same as Common item rarity in Dota 2
	ColorsMap.SetString("community", "#70B04A"); // same as Community item quality in TF2
	ColorsMap.SetString("coral", "#FF7F50");
	ColorsMap.SetString("cornflowerblue", "#6495ED");
	ColorsMap.SetString("cornsilk", "#FFF8DC");
	ColorsMap.SetString("corrupted", "#A32C2E"); // same as Corrupted item quality in Dota 2
	ColorsMap.SetString("crimson", "#DC143C");
	ColorsMap.SetString("cyan", "#00FFFF");
	ColorsMap.SetString("darkblue", "#00008B");
	ColorsMap.SetString("darkcyan", "#008B8B");
	ColorsMap.SetString("darkgoldenrod", "#B8860B");
	ColorsMap.SetString("darkgray", "#A9A9A9");
	ColorsMap.SetString("darkgrey", "#A9A9A9");
	ColorsMap.SetString("darkgreen", "#006400");
	ColorsMap.SetString("darkkhaki", "#BDB76B");
	ColorsMap.SetString("darkmagenta", "#8B008B");
	ColorsMap.SetString("darkolivegreen", "#556B2F");
	ColorsMap.SetString("darkorange", "#FF8C00");
	ColorsMap.SetString("darkorchid", "#9932CC");
	ColorsMap.SetString("darkred", "#8B0000");
	ColorsMap.SetString("darksalmon", "#E9967A");
	ColorsMap.SetString("darkseagreen", "#8FBC8F");
	ColorsMap.SetString("darkslateblue", "#483D8B");
	ColorsMap.SetString("darkslategray", "#2F4F4F");
	ColorsMap.SetString("darkslategrey", "#2F4F4F");
	ColorsMap.SetString("darkturquoise", "#00CED1");
	ColorsMap.SetString("darkviolet", "#9400D3");
	ColorsMap.SetString("deeppink", "#FF1493");
	ColorsMap.SetString("deepskyblue", "#00BFFF");
	ColorsMap.SetString("dimgray", "#696969");
	ColorsMap.SetString("dimgrey", "#696969");
	ColorsMap.SetString("dodgerblue", "#1E90FF");
	ColorsMap.SetString("exalted", "#CCCCCD"); // same as Exalted item quality in Dota 2
	ColorsMap.SetString("firebrick", "#B22222");
	ColorsMap.SetString("floralwhite", "#FFFAF0");
	ColorsMap.SetString("forestgreen", "#228B22");
	ColorsMap.SetString("frozen", "#4983B3"); // same as Frozen item quality in Dota 2
	ColorsMap.SetString("fuchsia", "#FF00FF");
	ColorsMap.SetString("fullblue", "#0000FF");
	ColorsMap.SetString("fullred", "#FF0000");
	ColorsMap.SetString("gainsboro", "#DCDCDC");
	ColorsMap.SetString("genuine", "#4D7455"); // same as Genuine item quality in TF2
	ColorsMap.SetString("ghostwhite", "#F8F8FF");
	ColorsMap.SetString("gold", "#FFD700");
	ColorsMap.SetString("goldenrod", "#DAA520");
	ColorsMap.SetString("gray", "#CCCCCC"); // same as spectator team color
	ColorsMap.SetString("grey", "#CCCCCC");
	ColorsMap.SetString("green", "#3EFF3E");
	ColorsMap.SetString("greenyellow", "#ADFF2F");
	ColorsMap.SetString("haunted", "#38F3AB"); // same as Haunted item quality in TF2
	ColorsMap.SetString("honeydew", "#F0FFF0");
	ColorsMap.SetString("hotpink", "#FF69B4");
	ColorsMap.SetString("immortal", "#E4AE33"); // same as Immortal item rarity in Dota 2
	ColorsMap.SetString("indianred", "#CD5C5C");
	ColorsMap.SetString("indigo", "#4B0082");
	ColorsMap.SetString("ivory", "#FFFFF0");
	ColorsMap.SetString("khaki", "#F0E68C");
	ColorsMap.SetString("lavender", "#E6E6FA");
	ColorsMap.SetString("lavenderblush", "#FFF0F5");
	ColorsMap.SetString("lawngreen", "#7CFC00");
	ColorsMap.SetString("legendary", "#D32CE6"); // same as Legendary item rarity in Dota 2
	ColorsMap.SetString("lemonchiffon", "#FFFACD");
	ColorsMap.SetString("lightblue", "#ADD8E6");
	ColorsMap.SetString("lightcoral", "#F08080");
	ColorsMap.SetString("lightcyan", "#E0FFFF");
	ColorsMap.SetString("lightgoldenrodyellow", "#FAFAD2");
	ColorsMap.SetString("lightgray", "#D3D3D3");
	ColorsMap.SetString("lightgrey", "#D3D3D3");
	ColorsMap.SetString("lightgreen", "#99FF99");
	ColorsMap.SetString("lightpink", "#FFB6C1");
	ColorsMap.SetString("lightsalmon", "#FFA07A");
	ColorsMap.SetString("lightseagreen", "#20B2AA");
	ColorsMap.SetString("lightskyblue", "#87CEFA");
	ColorsMap.SetString("lightslategray", "#778899");
	ColorsMap.SetString("lightslategrey", "#778899");
	ColorsMap.SetString("lightsteelblue", "#B0C4DE");
	ColorsMap.SetString("lightyellow", "#FFFFE0");
	ColorsMap.SetString("lime", "#00FF00");
	ColorsMap.SetString("limegreen", "#32CD32");
	ColorsMap.SetString("linen", "#FAF0E6");
	ColorsMap.SetString("magenta", "#FF00FF");
	ColorsMap.SetString("maroon", "#800000");
	ColorsMap.SetString("mediumaquamarine", "#66CDAA");
	ColorsMap.SetString("mediumblue", "#0000CD");
	ColorsMap.SetString("mediumorchid", "#BA55D3");
	ColorsMap.SetString("mediumpurple", "#9370D8");
	ColorsMap.SetString("mediumseagreen", "#3CB371");
	ColorsMap.SetString("mediumslateblue", "#7B68EE");
	ColorsMap.SetString("mediumspringgreen", "#00FA9A");
	ColorsMap.SetString("mediumturquoise", "#48D1CC");
	ColorsMap.SetString("mediumvioletred", "#C71585");
	ColorsMap.SetString("midnightblue", "#191970");
	ColorsMap.SetString("mintcream", "#F5FFFA");
	ColorsMap.SetString("mistyrose", "#FFE4E1");
	ColorsMap.SetString("moccasin", "#FFE4B5");
	ColorsMap.SetString("mythical", "#8847FF"); // same as Mythical item rarity in Dota 2
	ColorsMap.SetString("navajowhite", "#FFDEAD");
	ColorsMap.SetString("navy", "#000080");
	ColorsMap.SetString("normal", "#B2B2B2"); // same as Normal item quality in TF2
	ColorsMap.SetString("oldlace", "#FDF5E6");
	ColorsMap.SetString("olive", "#9EC34F");
	ColorsMap.SetString("olivedrab", "#6B8E23");
	ColorsMap.SetString("orange", "#FFA500");
	ColorsMap.SetString("orangered", "#FF4500");
	ColorsMap.SetString("orchid", "#DA70D6");
	ColorsMap.SetString("palegoldenrod", "#EEE8AA");
	ColorsMap.SetString("palegreen", "#98FB98");
	ColorsMap.SetString("paleturquoise", "#AFEEEE");
	ColorsMap.SetString("palevioletred", "#D87093");
	ColorsMap.SetString("papayawhip", "#FFEFD5");
	ColorsMap.SetString("peachpuff", "#FFDAB9");
	ColorsMap.SetString("peru", "#CD853F");
	ColorsMap.SetString("pink", "#FFC0CB");
	ColorsMap.SetString("plum", "#DDA0DD");
	ColorsMap.SetString("powderblue", "#B0E0E6");
	ColorsMap.SetString("purple", "#800080");
	ColorsMap.SetString("rare", "#4B69FF"); // same as Rare item rarity in Dota 2
	ColorsMap.SetString("red", "#FF4040"); // same as RED/Terrorist team color
	ColorsMap.SetString("rosybrown", "#BC8F8F");
	ColorsMap.SetString("royalblue", "#4169E1");
	ColorsMap.SetString("saddlebrown", "#8B4513");
	ColorsMap.SetString("salmon", "#FA8072");
	ColorsMap.SetString("sandybrown", "#F4A460");
	ColorsMap.SetString("seagreen", "#2E8B57");
	ColorsMap.SetString("seashell", "#FFF5EE");
	ColorsMap.SetString("selfmade", "#70B04A"); // same as Self-Made item quality in TF2
	ColorsMap.SetString("sienna", "#A0522D");
	ColorsMap.SetString("silver", "#C0C0C0");
	ColorsMap.SetString("skyblue", "#87CEEB");
	ColorsMap.SetString("slateblue", "#6A5ACD");
	ColorsMap.SetString("slategray", "#708090");
	ColorsMap.SetString("slategrey", "#708090");
	ColorsMap.SetString("snow", "#FFFAFA");
	ColorsMap.SetString("springgreen", "#00FF7F");
	ColorsMap.SetString("steelblue", "#4682B4");
	ColorsMap.SetString("strange", "#CF6A32"); // same as Strange item quality in TF2
	ColorsMap.SetString("tan", "#D2B48C");
	ColorsMap.SetString("teal", "#008080");
	ColorsMap.SetString("thistle", "#D8BFD8");
	ColorsMap.SetString("tomato", "#FF6347");
	ColorsMap.SetString("turquoise", "#40E0D0");
	ColorsMap.SetString("uncommon", "#B0C3D9"); // same as Uncommon item rarity in Dota 2
	ColorsMap.SetString("unique", "#FFD700"); // same as Unique item quality in TF2
	ColorsMap.SetString("unusual", "#8650AC"); // same as Unusual item quality in TF2
	ColorsMap.SetString("valve", "#A50F79"); // same as Valve item quality in TF2
	ColorsMap.SetString("vintage", "#476291"); // same as Vintage item quality in TF2
	ColorsMap.SetString("violet", "#EE82EE");
	ColorsMap.SetString("wheat", "#F5DEB3");
	ColorsMap.SetString("white", "#FFFFFF");
	ColorsMap.SetString("whitesmoke", "#F5F5F5");
	ColorsMap.SetString("yellow", "#FFFF00");
	ColorsMap.SetString("yellowgreen", "#9ACD32");
}

