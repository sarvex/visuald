module dllmain;

import std.c.windows.windows;
import comutil;
import logutil;
import register;
import winctrl;

version(D_Version2)
{
	import core.runtime;
	import core.memory;
//	import core.thread;
	import core.dll_helper;
}
else
{
	import std.gc;
	import std.thread;
}

mixin(d2_shared ~ " HINSTANCE g_hInst;");

///////////////////////////////////////////////////////////////////////
version(MAIN)
{
	int main()
	{
		VSDllRegisterServer(("Software\\Microsoft\\VisualStudio\\9.0D"w).ptr);
		//VSDllUnregisterServerUser(("Software\\Microsoft\\VisualStudio\\9.0D"w).ptr);
		return 0;
	}
}
else // !version(MAIN)
{
version(D_Version2)
{
	extern (C) void _moduleTlsCtor();
	extern (C) void _moduleTlsDtor();
}
else
{
extern (C)
{
	void gc_init();
	void gc_term();
	void _minit();
	void _moduleCtor();
	void _moduleDtor();
	void _moduleUnitTests();
}
} // !version(D_Version2)

extern (Windows)
BOOL DllMain(HINSTANCE hInstance, ULONG ulReason, LPVOID pvReserved)
{
	switch (ulReason)
	{
		case DLL_PROCESS_ATTACH:
version(D_Version2)
{
			if(!dll_process_attach(hInstance, true))
				return false;
			g_hInst = hInstance;
}
else
{
			// asm { int 3; }
			g_hInst = hInstance;
			gc_init();              // initialize GC
			_minit();               // initialize module list
			_moduleCtor();          // run module constructors
			_moduleUnitTests();  // run module unit tests

}
			initWinControls(g_hInst);
			//MessageBoxA(cast(HANDLE)0, "Hi", "there", 0);

			logCall("DllMain(DLL_PROCESS_ATTACH)");
			break;

		case DLL_PROCESS_DETACH:
			logCall("DllMain(DLL_PROCESS_DETACH)");
version(D_Version2)
{
			dll_process_detach( hInstance, true );
}
else
{
			_moduleDtor();
			gc_term();			// shut down GC
}
			break;

		case DLL_THREAD_ATTACH:
version(D_Version2) 
{
			dll_thread_attach( true, true );
}
else
{
			Thread.thread_attach();
}
			logCall("DllMain(DLL_THREAD_ATTACH, id=%x)", GetCurrentThreadId());
			break;

		case DLL_THREAD_DETACH:
			logCall("DllMain(DLL_THREAD_DETACH, id=%x)", GetCurrentThreadId());
version(D_Version2) 
{
			dll_thread_detach( true, true );
}
else
{
			Thread.thread_detach();
}
			break;
	}
	return true;
}

extern (Windows)
void RunDLLRegister(HWND hwnd, HINSTANCE hinst, LPSTR lpszCmdLine, int nCmdShow)
{
	wstring ws = to_wstring(lpszCmdLine) ~ cast(wchar)0;
	VSDllRegisterServer(ws.ptr);
}

extern (Windows)
void RunDLLUnregister(HWND hwnd, HINSTANCE hinst, LPSTR lpszCmdLine, int nCmdShow)
{
	wstring ws = to_wstring(lpszCmdLine) ~ cast(wchar)0;
	VSDllUnregisterServer(ws.ptr);
}

} // !version(MAIN)

///////////////////////////////////////////////////////////////////////
// only the first export has a '_' prefix
//extern(C) export void dummy () { }
