#include <sourcemod>
#include <regex>
#include <adt_trie>

#pragma semicolon 1

public Plugin myinfo =
{
    name        =    "GFL AutoMod",
    author        =    "Infra",
    description    =    "AutoMod - Deal punishments for text chat violations",
    version        =    "1.0.2",
	url        =    "https://gflclan.com/profile/45876-infra/"
};

Handle CvarEnable = INVALID_HANDLE;
Handle REGEXSections = INVALID_HANDLE;
Handle ChatREGEXList = INVALID_HANDLE;
Handle CmdREGEXList = INVALID_HANDLE;
Handle NameREGEXList = INVALID_HANDLE;
Handle CurrentSection = INVALID_HANDLE;
Handle ClientLimits[MAXPLAYERS+1]; 

public void OnPluginStart()
{
	CvarEnable = CreateConVar("regexfilter_enable","1","REGEXFILTER Enabled",FCVAR_PLUGIN|FCVAR_REPLICATED|FCVAR_NOTIFY);
	
	REGEXSections = CreateArray();
	ChatREGEXList = CreateArray(2);
	CmdREGEXList = CreateArray(2);
	NameREGEXList = CreateArray(2);
	char mapname[64];
	
	GetCurrentMap(mapname, sizeof(mapname));
	Format(mapname,sizeof(mapname),"configs/GFL-AutoMod-Blocklist-%s.cfg",mapname);
	
	LoadExpressions("configs/GFL-AutoMod-Blocklist.cfg");
	LoadExpressions(mapname);
	
	RegConsoleCmd("say", Command_SayHandle);
	RegConsoleCmd("say_team", Command_SayHandle);
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	char regexfile[128];
	
	BuildPath(Path_SM, regexfile ,sizeof(regexfile),"configs/GFL-AutoMod-Blocklist.cfg");
	bool load = FileExists(regexfile);
	
	char mapname[64];
	GetCurrentMap(mapname, sizeof(mapname));
	BuildPath(Path_SM, regexfile ,sizeof(regexfile),"configs/GFL-AutoMod-Blocklist-%s.cfg",mapname);
	bool load2 = FileExists(regexfile);
	
	if((load == false) && (load2 == false)) 
	{
		LogMessage("[GFL AutoMod] No config file found. Aborting...");	
		return APLRes_Failure;
	}
	return APLRes_Success;
}

public void OnMapStart()
{
	ClientLimits[0] = CreateTrie();
}

public void OnMapEnd()
{
	CloseHandle(ClientLimits[0]);
}

public bool OnClientConnect(int client, char[] rejectmsg, int maxlen)
{
	ClientLimits[client] = CreateTrie();
	return true;
}

public void OnClientDisconnect(client)
{
	CloseHandle(ClientLimits[client]);
}

public Action Command_SayHandle(int client, int args)
{
	if(!GetConVarInt(CvarEnable))
	{
		return Plugin_Continue;
	}
	
	char text[192];
	if (IsChatTrigger() || GetCmdArgString(text, sizeof(text)) < 1)
	{
		return Plugin_Continue;
	}
	
	int begin, end = GetArraySize(ChatREGEXList);
	RegexError ret = REGEX_ERROR_NONE;
	bool changed = false;
	Handle arr[2];
	Handle CurrRegex, CurrInfo;
	any val;
	char strval[192];
	
	while(begin != end)
	{
		GetArrayArray(ChatREGEXList,begin,arr,2);
		CurrRegex = arr[0];
		CurrInfo = arr[1];
		val = MatchRegex(CurrRegex, text, ret);
		
		if((val > 0) && (ret == REGEX_ERROR_NONE))
		{
			if(GetTrieValue(CurrInfo, "immunity", val))
			{
				if(CheckCommandAccess(client,"", val, true))
				{
					return Plugin_Continue;
				}
			}
			
			if(GetTrieString(CurrInfo, "warn", strval, sizeof(strval) ))
			{
				if(!client) 
					PrintToServer("[\x02GFL AutoMod\x01]\x02 %s",strval);
				else 
					PrintToChat(client, "[\x02GFL AutoMod\x01]\x02 %s",strval);
			}
			
			if(GetTrieString(CurrInfo, "action", strval, sizeof(strval) ))
			{
				ParseAndExecute(client, strval, sizeof(strval));
			}
			
			if(GetTrieValue(CurrInfo, "limit", val))
			{
				any at;
				FormatEx(strval, sizeof(strval), "%i", CurrRegex);
				GetTrieValue(ClientLimits[client], strval, at);	
				at++;
				
				int mod;
				if(GetTrieValue(CurrInfo, "forgive", mod))
				{
					float datiem;
					FormatEx(strval, sizeof(strval), "%i-limit", CurrRegex);
					if(!GetTrieValue(ClientLimits[client], strval, any:datiem))
					{
						datiem = GetGameTime();
						SetTrieValue(ClientLimits[client], strval, any:datiem);
					}	

					datiem = GetGameTime() - datiem;
					int datiemint = RoundToCeil(datiem);
					
					at = at - (datiemint % mod);
				}
				
				SetTrieValue(ClientLimits[client], strval, at);
				
				if(at > val)
				{
					if(GetTrieString(CurrInfo, "punish", strval, sizeof(strval)))
					{
						ParseAndExecute(client,strval, sizeof(strval));
					}
					return Plugin_Handled;
				}
			}
			
			if(GetTrieValue(CurrInfo, "block", val))
			{
				return Plugin_Handled;
			}
			
			if(GetTrieValue(CurrInfo, "replace", val))
			{
				changed = true;
				int rand = GetRandomInt(0, GetArraySize(Handle:val) - 1);
				
				Handle dp = GetArrayCell(Handle:val,rand);
				ResetPack(dp);
				Handle cregex = Handle:ReadPackCell(dp);
				ReadPackString(dp,strval, sizeof(strval) );
				
				if(cregex == INVALID_HANDLE) 
					cregex = CurrRegex;
				
				rand = MatchRegex(cregex, text, ret);
				if((rand > 0) && (ret == REGEX_ERROR_NONE))
				{
					char[][] strarray = new char[rand][192];
					for(new a = 0; a < rand; a++)
					{
						GetRegexSubString(cregex, a, strarray[a], sizeof(strval) );
					}
					
					for(new a = 0; a < rand; a++)
					{
						ReplaceString(text, sizeof(text), strarray[a], strval);
					}
					
					begin = 0;
				}
			}
		}
		begin++;
	}
	
	if(changed == true) 
	{
		if(client != 0) 
		{
			FakeClientCommand(client,"say %s", text);
			return Plugin_Continue;
		}
		else
		{
			ServerCommand("say %s", text);
			return Plugin_Handled;
		}
	}
	
	return Plugin_Continue;
}

stock LoadExpressions(char[] file)
{
	char regexfile[128];
	BuildPath(Path_SM, regexfile ,sizeof(regexfile), file);
	
	if(!FileExists(regexfile)) 
	{
		LogMessage("%s not parsed...file doesnt exist!", file);
		return 0;
	}
	
	Handle Parser = SMC_CreateParser();
	SMC_SetReaders(Parser, HandleNewSection, HandleKeyValue, HandleEndSection);
	SMC_SetParseEnd(Parser, HandleEnd);
	SMC_ParseFile(Parser, regexfile);
	CloseHandle(Parser);
	
	return 1;
}

public void HandleEnd(Handle smc, bool halted, bool failed)
{
	if(halted)
	{
		LogError("[GFL AutoMod] File could not be parsed completely, please check for errors. Continuing...");
	}
	
	if(failed)
	{
		LogError("[GFL AutoMod] Failed to parse file! Aborted.");
	}
}

public SMCResult HandleNewSection(Handle smc, const char[] name, bool opt_quotes)
{
	CurrentSection = CreateTrie();
	SetTrieString(CurrentSection, "name", name);
	PushArrayCell(REGEXSections,CurrentSection);
}

public SMCResult HandleKeyValue(Handle smc, const char[] key, const char[] value, bool key_quotes, bool value_quotes)
{
	if(!strcmp(key, "chatpattern", false)) 
	{
		RegisterExpression(value, CurrentSection, ChatREGEXList);
	}
	else if(!strcmp(key, "cmdpattern", false) || !strcmp(key, "commandkeyword", false))
	{
		RegisterExpression(value, CurrentSection, CmdREGEXList);
	}
	else if(!strcmp(key, "namepattern", false))
	{
		RegisterExpression(value, CurrentSection, NameREGEXList);
	}
	else if(!strcmp(key, "replace", false))
	{
		any val;
		if(!GetTrieValue(CurrentSection, "replace", val))
		{
			val = CreateArray();
			SetTrieValue(CurrentSection,"replace",val);
		}
		AddReplacement(value,val);
	}
	else if(!strcmp(key, "replacepattern", false))
	{
		any val;
		if(!GetTrieValue(CurrentSection, "replace", val))
		{
			val = CreateArray();
			SetTrieValue(CurrentSection,"replace",val);
		}
		AddPatternReplacement(value,val);
	}
	else if(!strcmp(key, "block", false))
	{
		SetTrieValue(CurrentSection,"block",1);
	}
	else if(!strcmp(key, "action", false))
	{
		SetTrieString(CurrentSection,"action",value);
	}
	else if(!strcmp(key, "warn", false))
	{
		SetTrieString(CurrentSection,"warn",value);
	}
	else if(!strcmp(key, "limit", false))
	{
		SetTrieValue(CurrentSection,"limit",StringToInt(value));
	}
	else if(!strcmp(key, "forgive", false))
	{
		SetTrieValue(CurrentSection,"forgive",StringToInt(value));
	}
	else if(!strcmp(key, "punish", false))
	{
		SetTrieString(CurrentSection,"punish",value);
	}
	else if(!strcmp(key, "immunity", false))
	{
		SetTrieValue(CurrentSection,"immunity",ReadFlagString(value));
	}
}

public SMCResult HandleEndSection(Handle smc)
{
	CurrentSection = INVALID_HANDLE;
}

stock RegisterExpression(const char[] key, Handle curr, Handle array)
{
	char expression[192];
	int flags = ParseExpression(key, expression, sizeof(expression));
	if(flags == -1)
	{
		return;
	}
	
	char errno[128]; 
	RegexError errcode;
	Handle compiled = CompileRegex(expression, flags, errno, sizeof(errno), errcode);
	
	if(compiled == INVALID_HANDLE)
	{
		LogMessage("Error occured while compiling expression %s with flags %s, error: %s, errcode: %d", 
			expression, flags, errno, errcode);
	}
	else 
	{
		int arr[2];
		arr[0] = _:compiled;
		arr[1] = _:curr;
		PushArrayArray(array, arr, 2);
	}
}

stock ParseExpression(const String:key[], String:expression[], len)
{
	strcopy(expression, len, key);
	TrimString(expression);
	
	int flags, a, b, c;
	
	if(expression[strlen(expression) - 1] == '\'')
	{
		for(; expression[flags] != '\0'; flags++)
		{
			if(expression[flags] == '\'')
			{
				a++;
				b = c;
				c = flags;
			}
		}
		
		if(a < 2) 
		{
			LogError("[GFL AutoMod] File line malformed: %s, please check for errors. Continuing...",key);
			return -1;
		}
		
		else
		{
			expression[b] = '\0';
			expression[c] = '\0';
			flags = FindREGEXFlags(expression[b + 1]);
			
			TrimString(expression);
			
			if(a > 2 && expression[0] == '\'')
			{
				strcopy(expression, strlen(expression) - 1, expression[1]);
			}
		}
	}
	
	return flags;
}

stock FindREGEXFlags(const String:flags[])
{
	char buffer[7][16];
	buffer[0][0] = '\0';
	buffer[1][0] = '\0';
	buffer[2][0] = '\0';
	buffer[3][0] = '\0';
	buffer[4][0] = '\0';
	buffer[5][0] = '\0';
	buffer[6][0] = '\0';

	ExplodeString(flags, "|", buffer, 7, 16 );

	int intflags = 0;
	for(new i = 0; i < 7; i++)
	{
		if(buffer[i][0] == '\0') 
			continue;
		
		if(!strcmp(buffer[i],"CASELESS",false)) 
			intflags |= PCRE_CASELESS;
		else if(!strcmp(buffer[i],"MULTILINE",false)) 
			intflags |= PCRE_MULTILINE;
		else if(!strcmp(buffer[i],"DOTALL",false)) 
			intflags |= PCRE_DOTALL;
		else if(!strcmp(buffer[i],"EXTENDED",false)) 
			intflags |= PCRE_EXTENDED;
		else if(!strcmp(buffer[i],"UNGREEDY",false)) 
			intflags |= PCRE_UNGREEDY;
		else if(!strcmp(buffer[i],"UTF8",false)) 
			intflags |= PCRE_UTF8 ;
		else if(!strcmp(buffer[i],"NO_UTF8_CHECK",false)) 
			intflags |= PCRE_NO_UTF8_CHECK;
	}
	
	return intflags;
}

stock AddReplacement(const String:val[], Handle:array)
{
	Handle dp = CreateDataPack();
	WritePackCell(dp, _:INVALID_HANDLE);
	WritePackString(dp, val);
	
	PushArrayCell(array,dp);
}

stock AddPatternReplacement(const String:val[], Handle:array)
{
	char expression[192];
	int flags = ParseExpression(val, expression, sizeof(expression) );
	if(flags == -1)
		return;
	
	char errno[128];
	RegexError errcode;
	Handle compiled = CompileRegex(expression, flags, errno, sizeof(errno), errcode);
	
	if(compiled == INVALID_HANDLE)
	{
		LogMessage("Error occured while compiling expression %s with flags %s, error: %s, errcode: %d", 
			expression, flags, errno, errcode);
	}
	
	else
	{
		Handle dp = CreateDataPack();
		WritePackCell(dp,_:compiled);
		WritePackString(dp, "");
	
		PushArrayCell(array,dp);
	}
}

stock ParseAndExecute(client, String:cmd[], len)
{
	char repl[192];
	
	if(client == 0) 
	{
		FormatEx(repl, sizeof(repl), "0");
	}
	else 
	{
		FormatEx(repl, sizeof(repl), "%i", GetClientUserId(client));
	}

	ReplaceString(cmd, len, "%u", repl);
	
	if(client != 0) 
	{
		FormatEx(repl, sizeof(repl), "%i", client);
	}
	
	ReplaceString(cmd, len, "%i", repl);
	
	GetClientName(client, repl, sizeof(repl));
	ReplaceString(cmd, len, "%n", repl);
	
	ServerCommand(cmd);
}