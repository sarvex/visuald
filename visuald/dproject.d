module dproject;

import std.c.windows.windows;
import std.c.windows.com;
import std.windows.charset;
import std.string;
import std.utf;
import std.file;
import std.path;
import std.conv;

import xml = xmlwrap;

import sdk.vsi.vsshell;
import sdk.vsi.vsshell80;
import sdk.vsi.vsshell90;
import sdk.vsi.fpstfmt;
import dte = sdk.vsi.dte80a;

import comutil;
import logutil;

import dpackage;
import propertypage;
import hierarchy;
import hierutil;
import chiernode;
import chiercontainer;
import build;
import config;

import dllmain : g_hInst;

const kPlatform = "Win32";

extern(Windows)
{

struct s_IMAGELIST;
alias s_IMAGELIST *HIMAGELIST;

export HANDLE LoadImageA(HINSTANCE hinst, LPCTSTR lpszName, UINT uType, int cxDesired, int cyDesired, UINT fuLoad);

export HIMAGELIST ImageList_LoadImageA(HINSTANCE hi, LPCTSTR lpbmp, int cx, int cGrow, COLORREF crMask, UINT uType, UINT uFlags);
export BOOL ImageList_Destroy(HIMAGELIST imgl);

HINSTANCE ShellExecuteW(HWND hwnd, LPCWSTR lpOperation, LPCWSTR lpFile, LPCWSTR lpParameters, LPCWSTR lpDirectory, INT nShowCmd);

UINT RegisterClipboardFormatW(LPCWSTR lpszFormat);

UINT DragQueryFileW(HANDLE hDrop, UINT iFile, LPWSTR lpszFile, UINT cch);
}

///////////////////////////////////////////////////////////////


///////////////////////////////////////////////////////////////

class ProjectFactory : DComObject, IVsProjectFactory
{
	this(Package pkg)
	{
		mPackage = pkg;
	}

	HRESULT QueryInterface(IID* riid, void** pvObject)
	{
		//mixin(LogCallMix);

		if(queryInterface!(IVsProjectFactory) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	override int CanCreateProject(in wchar* pszFilename, in uint grfCreateFlags, int* pfCanCreate)
	{
		mixin(LogCallMix);

		*pfCanCreate = 1;
		return S_OK;
	}
	override int Close()
	{
		mixin(LogCallMix);

		return S_OK;
	}
	override int CreateProject(in wchar* pszFilename, in wchar* pszLocation, in wchar* pszName, in VSCREATEPROJFLAGS grfCreateFlags, 
				   in IID* iidProject, void** ppvProject, BOOL* pfCanceled)
	{
		mixin(LogCallMix);

		version(none)
		{
			CoInitialize(null);
 			VCProjectEngine spEngine;
			int hr = CoCreateInstance(&VCProjectEngineObject.iid, null, CLSCTX_INPROC_SERVER, &VCProjectEngine.iid, cast(void*)&spEngine);
			if( hr != S_OK || !spEngine )
			{
				CoUninitialize(); 
				return returnError(E_FAIL);
			}

			// Open an existing project.
			IDispatch *spDispProj = spEngine.CreateProject(pszFilename);
			if(!spDispProj)
			{
				CoUninitialize(); 
				return returnError(E_FAIL);
			}
		} // version

		if(grfCreateFlags & CPF_OPENFILE)
		{
			string filename = to_string(pszFilename);
			string name = getBaseName(filename);

			Project prj = new Project(this, name, filename);
			*pfCanceled = 0;
			return prj.QueryInterface(iidProject, ppvProject);
		}
		else if(grfCreateFlags & CPF_CLONEFILE)
		{
			string src  = to_string(pszFilename);
			string name = to_string(pszName);
			string dest = to_string(pszLocation) ~ name ~ "." ~ toUTF8(g_projectFileExtensions);

			if(!cloneProject(src, dest))
				return returnError(E_FAIL);

			//std.file.copy(to_wstring(pszFilename), to_wstring(pszLocation));
			Project prj = new Project(this, name, dest);
			*pfCanceled = 0;
			return prj.QueryInterface(iidProject, ppvProject);
		}
		return returnError(E_NOTIMPL);
	}
	override int SetSite(IServiceProvider psp)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	///////////////////////////////////////////////////////////////
	bool cloneProjectFiles(string srcdir, string destdir, xml.Element node)
	{
		xml.Element[] folderItems = xml.elementsById(node, "Folder");
		foreach(folder; folderItems)
			if (!cloneProjectFiles(srcdir, destdir, folder))
				return false;

		xml.Element[] fileItems = xml.elementsById(node, "File");
		foreach(file; fileItems)
		{
			string fileName = xml.getAttribute(file, "path");
			std.file.copy(srcdir ~ fileName, destdir ~ fileName);
		}
		return true;
	}

	bool cloneProject(string src, string dest)
	{
		try
		{
			string srcdir = getDirName(src) ~ "\\";
			string destdir = getDirName(dest) ~ "\\";

			auto doc = Project.readXML(src);
			if(!doc)
				return false;

			if(!cloneProjectFiles(srcdir, destdir, xml.getRoot(doc)))
				return false;

			if(!Project.saveXML(doc, dest))
				return false;

			return true;
		}
		catch(Exception e)
		{
			logCall(e.toString());
		}
		return false;
	}

private:
	Package mPackage;
}

class ExtProjectItems : DisposingDispatchObject, dte.ProjectItems
{
	this(ExtProject prj)
	{
		mExtProject = prj;
	}

	static ComTypeInfoHolder mTypeHolder;

	override ComTypeInfoHolder getTypeHolder () { return mTypeHolder; }
	
	override void Dispose()
	{
	}

	override HRESULT QueryInterface(IID* riid, void** pvObject)
	{
		//mixin(LogCallMix);

		if(queryInterface!(dte.ProjectItems) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	override int Item( 
		/* [in] */ in VARIANT index,
		/* [retval][out] */ dte.ProjectItem *lppcReturn)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int Parent( 
		/* [retval][out] */ IDispatch* lppptReturn)
	{
		mixin(LogCallMix);
		*lppptReturn = addref(mExtProject);
		return S_OK;
	}

	override int Count( 
		/* [retval][out] */ int *lplReturn)
	{
		logCall("%s.get_Count(lplReturn=%s)", this, lplReturn);
		*lplReturn = 0;
		return S_OK;
	}

	override int _NewEnum( 
		/* [retval][out] */ IUnknown *lppiuReturn)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int DTE( 
		/* [retval][out] */ dte.DTE	*lppaReturn)
	{
		logCall("%s.get_DTE()", this);
		return returnError(E_NOTIMPL);
	}

	override int Kind( 
		/* [retval][out] */ BSTR *lpbstrFileName)
	{
		logCall("%s.get_Kind(lpbstrFileName=%s)", this, lpbstrFileName);
		return returnError(E_NOTIMPL);
	}

	override int AddFromFile( 
		/* [in] */ in BSTR FileName,
		/* [retval][out] */ dte.ProjectItem *lppcReturn)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int AddFromTemplate( 
		/* [in] */ in BSTR FileName,
		/* [in] */ in BSTR Name,
		/* [retval][out] */ dte.ProjectItem *lppcReturn)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int AddFromDirectory( 
		/* [in] */ in BSTR Directory,
		/* [retval][out] */ dte.ProjectItem *lppcReturn)
	{
		logCall("AddFromDirectory(Directory=%s, lppcReturn=%s)", _toLog(Directory), _toLog(lppcReturn));
		return returnError(E_NOTIMPL);
	}

	override int ContainingProject( 
		/* [retval][out] */ dte.Project* ppProject)
	{
		mixin(LogCallMix);
		*ppProject = addref(mExtProject);
		return S_OK;
	}

	override int AddFolder( 
		BSTR Name,
		/* [defaultvalue] */ BSTR Kind,
		/* [retval][out] */ dte.ProjectItem *pProjectItem)
	{
		logCall("AddFolder(Kind=%s, pProjectItem=%s)", _toLog(Kind), _toLog(pProjectItem));
		return returnError(E_NOTIMPL);
	}

	override int AddFromFileCopy( 
		BSTR FilePath,
		/* [retval][out] */ dte.ProjectItem *pProjectItem)
	{
		logCall("AddFromFileCopy(FilePath=%s, pProjectItem=%s)", _toLog(FilePath), _toLog(pProjectItem));
		return returnError(E_NOTIMPL);
	}

	ExtProject mExtProject;
};

class ExtProject : DisposingDispatchObject, dte.Project
{
	this(Project prj)
	{
		mProject = prj;
		mProjectItems = addref(new ExtProjectItems(this));
	}

	override void Dispose()
	{
		mProjectItems = release(mProjectItems);
	}

	override HRESULT QueryInterface(IID* riid, void** pvObject)
	{
		//mixin(LogCallMix);

		if(queryInterface!(dte.Project) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	// DTE.Project
	override int Name( 
		/* [retval][out] */ BSTR *lpbstrName)
	{
		logCall("get_Name(lpbstrName=%s)", _toLog(lpbstrName));
		*lpbstrName = allocBSTR(mProject.mCaption);
		return S_OK;
	}

	override int Name( 
		/* [in] */ in BSTR bstrName)
	{
		logCall("put_Name(bstrName=%s)", _toLog(bstrName));
		mProject.mCaption = to_string(bstrName);
		return S_OK;
	}

	override int FileName( 
		/* [retval][out] */ BSTR *lpbstrName)
	{
		logCall("get_FileName(lpbstrName=%s)", _toLog(lpbstrName));
		*lpbstrName = allocBSTR(mProject.mFilename);
		return S_OK;
	}

	override int IsDirty( 
		/* [retval][out] */ VARIANT_BOOL *lpfReturn)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int IsDirty( 
		/* [in] */ in VARIANT_BOOL Dirty)
	{
		logCall("put_IsDirty(Dirty=%s)", _toLog(Dirty));
		return returnError(E_NOTIMPL);
	}

	override int Collection( 
		/* [retval][out] */ dte.Projects *lppaReturn)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int SaveAs( 
		/* [in] */ in BSTR NewFileName)
	{
		logCall("SaveAs(NewFileName=%s)", _toLog(NewFileName));
		return returnError(E_NOTIMPL);
	}

	override int DTE( 
		/* [retval][out] */ dte.DTE	*lppaReturn)
	{
		logCall("%s.get_DTE()", this);
		return returnError(E_NOTIMPL);
	}

	override int Kind( 
		/* [retval][out] */ BSTR *lpbstrName)
	{
		logCall("get_Kind(lpbstrName=%s)", _toLog(lpbstrName));
		wstring s = GUID2wstring(g_projectFactoryCLSID);
		*lpbstrName = allocwBSTR(s);
		return S_OK;
	}

	override int ProjectItems( 
		/* [retval][out] */ dte.ProjectItems* lppcReturn)
	{
		mixin(LogCallMix);
		*lppcReturn = addref(mProjectItems);
		return S_OK;
	}

	override int Properties( 
		/* [retval][out] */ dte.Properties *ppObject)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int UniqueName( 
		/* [retval][out] */ BSTR *lpbstrName)
	{
		logCall("get_UniqueName(lpbstrName=%s)", _toLog(lpbstrName));

		if (!mProject)
			return returnError(E_FAIL);

		IVsSolution srpSolution = queryService!(IVsSolution);
		if(!srpSolution)
			return returnError(E_FAIL);

		IVsHierarchy pIVsHierarchy = mProject; // ->GetIVsHierarchy();
		
		int hr = srpSolution.GetUniqueNameOfProject(pIVsHierarchy, lpbstrName);
		srpSolution.Release();

		return hr;
	}

	override int Object( 
		/* [retval][out] */ IDispatch* ProjectModel)
	{
		logCall("%s.get_Object(out ProjectModel=%s)", this, _toLog(&ProjectModel));
		*ProjectModel = addref(mProject);
		return S_OK;
	}

	override int Extender( 
		/* [in] */ in BSTR ExtenderName,
		/* [retval][out] */ IDispatch *Extender)
	{
		logCall("%s.get_Extender(ExtenderName=%s)", this, _toLog(ExtenderName));
		return returnError(E_NOTIMPL);
	}

	override int ExtenderNames( 
		/* [retval][out] */ VARIANT *ExtenderNames)
	{
		logCall("%s.get_ExtenderNames(ExtenderNames=%s)", this, _toLog(ExtenderNames));
		return returnError(E_NOTIMPL);
	}

	override int ExtenderCATID( 
		/* [retval][out] */ BSTR *pRetval)
	{
		logCall("get_ExtenderCATID(pRetval=%s)", _toLog(pRetval));
		return returnError(E_NOTIMPL);
	}

	override int FullName( 
		/* [retval][out] */ BSTR *lpbstrName)
	{
		logCall("get_FullName(lpbstrName=%s)", _toLog(lpbstrName));
		return FileName(lpbstrName);
	}

	override int Saved( 
		/* [retval][out] */ VARIANT_BOOL *lpfReturn)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int Saved( 
		/* [in] */ in VARIANT_BOOL SavedFlag)
	{
		logCall("put_Saved(SavedFlag=%s)", _toLog(SavedFlag));
		return returnError(E_NOTIMPL);
	}

	override int ConfigurationManager( 
		/* [retval][out] */ dte.ConfigurationManager* ppConfigurationManager)
	{
		mixin(LogCallMix);

		*ppConfigurationManager = mProject.getConfigurationManager();
		return S_OK;
	}

	override int Globals( 
		/* [retval][out] */ dte.Globals* ppGlobals)
	{
		mixin(LogCallMix);

		HRESULT hr = S_OK;
		// hr = CheckEnabledItem(this, &IID__DTE, L"Globals");
		// IfFailRet(hr);

		// if don't already have m_srpGlobals, get it from shell
		IVsExtensibility3 ext = queryService!(dte.IVsExtensibility, IVsExtensibility3);
		if(!ext)
			return E_FAIL;
		scope(exit) release(ext);

		dte.Globals globals;
		VARIANT varIVsGlobalsCallback;
		varIVsGlobalsCallback.vt = VT_UNKNOWN;
		IVsHierarchy pIVsHierarchy = mProject;
		hr = mProject.QueryInterface(&IID_IUnknown, cast(void**)&varIVsGlobalsCallback.punkVal);
		if(!FAILED(hr))
		{
			//! @todo fix: returns failure
			hr = ext.GetGlobalsObject(varIVsGlobalsCallback, cast(IUnknown*) &globals);
			varIVsGlobalsCallback.punkVal.Release();
		}

		*ppGlobals = globals;
		return hr;
	}

	override int Save( 
		/* [defaultvalue] */ BSTR FileName)
	{
		logCall("Save(FileName=%s)", _toLog(FileName));
		return returnError(E_NOTIMPL);
	}

	override int ParentProjectItem( 
		/* [retval][out] */ dte.ProjectItem *ppParentProjectItem)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int CodeModel( 
		/* [retval][out] */ dte.CodeModel *ppCodeModel)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int Delete()
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}


	//////////////////////////////////////////////////////////////
	static ComTypeInfoHolder mTypeHolder;
	static this()
	{
		mTypeHolder = new class ComTypeInfoHolder {
			override int GetIDsOfNames( 
				/* [size_is][in] */ LPOLESTR *rgszNames,
				/* [in] */ in UINT cNames,
				/* [size_is][out] */ MEMBERID *pMemId)
			{
				mixin(LogCallMix);
				if (cNames == 1 && to_string(*rgszNames) == "Name")
				{
					*pMemId = 1;
					return S_OK;
				}
				return returnError(E_NOTIMPL);
			}
		};
		addref(mTypeHolder);
	}

	override ComTypeInfoHolder getTypeHolder () { return mTypeHolder; }
	
	Project mProject;
	dte.ProjectItems mProjectItems;
}

///////////////////////////////////////////////////////////////////////

class Project : CVsHierarchy,
		IVsProject,
		IVsParentProject,
		IVsGetCfgProvider,
		IVsProject3,
		IVsHierarchyDeleteHandler,
		IVsAggregatableProject,
		IVsProjectFlavorCfgProvider,
		IPersistFileFormat,
		IVsProjectBuildSystem,
		IVsBuildPropertyStorage,
		IVsComponentUser,
		IVsDependencyProvider,
		ISpecifyPropertyPages,
		IPerPropertyBrowsing,
		dte.IVsGlobalsCallback,
		IVsHierarchyDropDataSource2,
		IVsHierarchyDropDataTarget,
		//IVsSccProject2,
		//IBuildDependencyUpdate,
		//IProjectEventsListener,
		//IProjectEventsProvider,
		//IReferenceContainerProvider,
		IVsProjectSpecialFiles
{
	static GUID iid = { 0x5840c881, 0x9d9e, 0x4a85, [ 0xb7, 0x6b, 0x50, 0xa9, 0x68, 0xdb, 0x22, 0xf9 ] };

	this(ProjectFactory factory, string name, string filename)
	{
		mFactory = factory;
		mName = name;
		mFilename = filename;
		mExtProject = addref(new ExtProject(this));
		mConfigProvider = addref(new ConfigProvider(this));
		
		parseXML();
	}
	
	void Dispose()
	{
		mConfigProvider = release(mConfigProvider);
		mExtProject = release(mExtProject);
		super.Dispose();
	}

	HRESULT QueryInterface(IID* riid, void** pvObject)
	{
		//mixin(LogCallMix);

		if(queryInterface!(Project) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsProject) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsProject2) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsProject3) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsHierarchyDeleteHandler) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsParentProject) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsGetCfgProvider) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(ISpecifyPropertyPages) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsAggregatableProject) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsProjectFlavorCfgProvider) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IPersist) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IPersistFileFormat) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsProjectBuildSystem) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsBuildPropertyStorage) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsComponentUser) (this, riid, pvObject))
			return S_OK;
		//if(queryInterface!(IVsDependencyProvider) (this, riid, pvObject))
		//	return S_OK;
		if(queryInterface!(dte.IVsGlobalsCallback) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsHierarchyDropDataSource) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsHierarchyDropDataSource2) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsHierarchyDropDataTarget) (this, riid, pvObject))
			return S_OK;
		//if(queryInterface!(IPerPropertyBrowsing) (this, riid, pvObject))
		//	return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	// IDispatch
	static ComTypeInfoHolder mTypeHolder;
	static this()
	{
		mTypeHolder = new class ComTypeInfoHolder {
			override int GetIDsOfNames( 
				/* [size_is][in] */ LPOLESTR *rgszNames,
				/* [in] */ in UINT cNames,
				/* [size_is][out] */ MEMBERID *pMemId)
			{
				mixin(LogCallMix);
				if (cNames == 1 && to_string(*rgszNames) == "Name")
				{
					*pMemId = 1;
					return S_OK;
				}
				if (cNames == 1 && to_string(*rgszNames) == "__id")
				{
					*pMemId = 2;
					return S_OK;
				}
				return returnError(E_NOTIMPL);
			}
		};
		addref(mTypeHolder);
	}

	override ComTypeInfoHolder getTypeHolder () { return mTypeHolder; }

	override int Invoke( 
		/* [in] */ in DISPID dispIdMember,
		/* [in] */ in IID* riid,
		/* [in] */ in LCID lcid,
		/* [in] */ in WORD wFlags,
		/* [out][in] */ DISPPARAMS *pDispParams,
		/* [out] */ VARIANT *pVarResult,
		/* [out] */ EXCEPINFO *pExcepInfo,
		/* [out] */ UINT *puArgErr)
	{
		mixin(LogCallMix);

		if(dispIdMember == 1 || dispIdMember == 2)
		{
			if(pDispParams.cArgs == 0)
				return GetProperty(VSITEMID_ROOT, VSHPROPID_Name, pVarResult);
		}
		return returnError(E_NOTIMPL);
	}

	// IVsProject
	override int IsDocumentInProject(in LPCOLESTR pszMkDocument, BOOL* pfFound, VSDOCUMENTPRIORITY* pdwPriority, VSITEMID* pitemid)
	{
		mixin(LogCallMix);

		string docName = to_string(pszMkDocument);
		if(!isabs(docName))
		{
			string root = getDirName(GetRootNode().GetFullPath());
			docName = root ~ "\\" ~ docName;
		}
		docName = tolower(docName);

		CHierNode node = searchNode(GetRootNode(), delegate (CHierNode n) { return n.GetCanonicalName() == docName; });
		if(node)
		{
			if(pfFound) *pfFound = true;
			if(pitemid) *pitemid = node is GetRootNode() ? VSITEMID_ROOT : node.GetVsItemID();
		}
		else
		{
			if(pfFound) *pfFound = false;
			if(pitemid) *pitemid = VSITEMID_NIL;
		}
		if (pdwPriority) *pdwPriority = DP_Unsupported;
		return S_OK;
	}

	override int OpenItem(in VSITEMID itemid, in GUID* rguidLogicalView, IUnknown punkDocDataExisting, IVsWindowFrame *ppWindowFrame)
	{
		mixin(LogCallMix);

		if(CFileNode pNode = cast(CFileNode) VSITEMID2Node(itemid))
			return OpenDoc(pNode, false /*fNewFile*/, 
					      false /*fUseOpenWith*/,
					      false  /*fShow*/,
					      rguidLogicalView,
					      &GUID_NULL, null,
					      punkDocDataExisting, 
					      ppWindowFrame);

		return returnError(E_UNEXPECTED);
	}

	override int GetItemContext(in VSITEMID itemid, IServiceProvider* ppSP)
	{
		logCall("GetItemContext(itemid=%s, ppSP=%s)", _toLog(itemid), _toLog(ppSP));

		// NOTE: this method allows a project to provide project context services 
		// to an item (document) editor. If the project does not need to provide special
		// services to its items then it should return NULL. Under no circumstances
		// should you return the IServiceProvider pointer that was passed to our
		// package from the Environment via IVsPackage::SetSite. The global services
		// will automatically be made available to editors. 
		*ppSP = null;
		return S_OK;
	}

	override int GenerateUniqueItemName(in VSITEMID itemidLoc, in wchar* pszExt, in wchar* pszSuggestedRoot, BSTR *pbstrItemName)
	{
		mixin(LogCallMix);

		// as we are using virtual folders, just suggest a file in the project directory
		string dir = getDirName(GetProjectNode().GetFullPath());
		string root = pszSuggestedRoot ? to_string(pszSuggestedRoot) : "File";
		string ext = pszExt ? to_string(pszExt) : ".d";

		for(int i = 1; i < int.max; i++)
		{
			string file = dir ~ "\\" ~ root ~ format("%d", i) ~ ext;
			if(!std.file.exists(file))
			{
				*pbstrItemName = allocBSTR(file);
				return S_OK;
			}
		}
		return returnError(E_FAIL);
	}

	override int GetMkDocument(in VSITEMID itemid, BSTR *pbstrMkDocument)
	{
		logCall("GetMkDocument(itemid=%s, pbstrMkDocument=%s)", _toLog(itemid), _toLog(pbstrMkDocument));

		if(CHierNode pNode = VSITEMID2Node(itemid))
		{
			*pbstrMkDocument = allocBSTR(pNode.GetFullPath());
			return S_OK;
		}
		return returnError(E_INVALIDARG);
	}

	override int AddItem(in VSITEMID itemidLoc, in VSADDITEMOPERATION dwAddItemOperation, in wchar* pszItemName,
	                     in ULONG cFilesToOpen, wchar** rgpszFilesToOpen, in HWND hwndDlgOwner, VSADDRESULT* pResult)
	{
		mixin(LogCallMix);

		return AddItemWithSpecific(
			/* [in]  VSITEMID              itemidLoc            */ itemidLoc,
			/* [in]  VSADDITEMOPERATION    dwAddItemOperation   */ dwAddItemOperation,
			/* [in]  LPCOLESTR             pszItemName          */ pszItemName,
			/* [in]  ULONG                 cFilesToOpen         */ cFilesToOpen,
			/* [in]  LPCOLESTR             rgpszFilesToOpen[]   */ rgpszFilesToOpen,
			/* [in]  HWND                  hwndDlg              */ hwndDlgOwner,
			/* [in]  VSSPECIFICEDITORFLAGS grfEditorFlags       */ VSSPECIFICEDITOR_DoOpen | VSSPECIFICEDITOR_UseView,
			/* [in]  REFGUID               rguidEditorType      */ &GUID_NULL,
			/* [in]  LPCOLESTR             pszPhysicalView      */ null,
			/* [in]  REFGUID               rguidLogicalView     */ &GUID_NULL, //LOGVIEWID_Primary,
			/* [out] VSADDRESULT *         pResult              */ pResult);
	}

	// IVsProject2
	override int RemoveItem( 
	    /* [in] */ in DWORD dwReserved,
	    /* [in] */ in VSITEMID itemid,
	    /* [retval][out] */ BOOL *pfResult)
	{
		mixin(LogCallMix);

		if(itemid == VSITEMID_ROOT || itemid == VSITEMID_NIL)
			return E_UNEXPECTED;

		int hr = DeleteItem(DELITEMOP_RemoveFromProject, itemid);
		*pfResult = SUCCEEDED(hr);

		return hr;
	}
        
	override int ReopenItem( 
	    /* [in] */ in VSITEMID itemid,
	    /* [in] */ in GUID* rguidEditorType,
	    /* [in] */ in wchar* pszPhysicalView,
	    /* [in] */ in GUID* rguidLogicalView,
	    /* [in] */ IUnknown punkDocDataExisting,
	    /* [retval][out] */ IVsWindowFrame *ppWindowFrame)
	{
		mixin(LogCallMix);

		if(CFileNode pNode = cast(CFileNode) VSITEMID2Node(itemid))
			return OpenDoc(pNode, false /*fNewFile*/, 
					      false /*fUseOpenWith*/,
					      false  /*fShow*/,
					      rguidLogicalView,
					      rguidEditorType, pszPhysicalView,
					      punkDocDataExisting, 
					      ppWindowFrame);

		return returnError(E_UNEXPECTED);
	}
        
	// IVsProject3
	override int AddItemWithSpecific( 
	    /* [in] */ in VSITEMID itemidLoc,
	    /* [in] */ in VSADDITEMOPERATION dwAddItemOperation,
	    /* [in] */ in wchar* pszItemName,
	    /* [in] */ in uint cFilesToOpen,
	    /* [size_is][in] */ wchar** rgpszFilesToOpen,
	    /* [in] */ in HWND hwndDlgOwner,
	    /* [in] */ in VSSPECIFICEDITORFLAGS grfEditorFlags,
	    /* [in] */ in GUID* rguidEditorType,
	    /* [in] */ in wchar* pszPhysicalView,
	    /* [in] */ in GUID* rguidLogicalView,
	    /* [retval][out] */ VSADDRESULT* pResult)
	{
		//  AddItemWithSpecific is used to add item(s) to the project and 
		//  additionally ask the project to open the item using the specified 
		//  editor information.  An extension of IVsProject::AddItem().

		mixin(LogCallMix);

		if(CHierContainer pNode = cast(CHierContainer) VSITEMID2Node(itemidLoc))
		{
			return AddItemSpecific(pNode,
				/* [in]  VSADDITEMOPERATION dwAddItemOperation */ dwAddItemOperation,
				/* [in]  LPCOLESTR pszItemName                 */ pszItemName,
				/* [in]  DWORD cFilesToOpen                    */ cFilesToOpen,
				/* [in]  LPCOLESTR rgpszFilesToOpen[]          */ rgpszFilesToOpen,
				/* [in]  HWND hwndDlg                          */ hwndDlgOwner,
				/* [in]  VSSPECIFICEDITORFLAGS grfEditorFlags  */ grfEditorFlags,
				/* [in]  REFGUID               rguidEditorType */ rguidEditorType,
				/* [in]  LPCOLESTR             pszPhysicalView */ pszPhysicalView,
				/* [in]  REFGUID               rguidLogicalView*/ rguidLogicalView,
				/* [out] VSADDRESULT *pResult                  */ pResult);
		}

		return returnError(E_UNEXPECTED);
	}
        
	override int OpenItemWithSpecific( 
	    /* [in] */ in VSITEMID itemid,
	    /* [in] */ in VSSPECIFICEDITORFLAGS grfEditorFlags,
	    /* [in] */ in GUID* rguidEditorType,
	    /* [in] */ in wchar* pszPhysicalView,
	    /* [in] */ in GUID* rguidLogicalView,
	    /* [in] */ IUnknown punkDocDataExisting,
	    /* [out] */ IVsWindowFrame *ppWindowFrame)
	{
		mixin(LogCallMix);

		return returnError(E_NOTIMPL);
	}
        
	override int TransferItem( 
	    /* [in] */ in wchar* pszMkDocumentOld,
	    /* [in] */ in wchar* pszMkDocumentNew,
	    /* [in] */ IVsWindowFrame punkWindowFrame)
	{
		mixin(LogCallMix);

		return returnError(E_NOTIMPL);
	}

	override int QueryDeleteItem( 
		/* [in] */ in VSDELETEITEMOPERATION dwDelItemOp,
		/* [in] */ in VSITEMID itemid,
		/* [retval][out] */ BOOL *pfCanDelete)
	{
//		mixin(LogCallMix);

		*pfCanDelete = (dwDelItemOp == DELITEMOP_RemoveFromProject);
		return S_OK;
	}

	override int DeleteItem( 
		/* [in] */ in VSDELETEITEMOPERATION dwDelItemOp,
		/* [in] */ in VSITEMID itemid)
	{
		mixin(LogCallMix);

		// the root item will be removed without asking the project itself
		if(itemid == VSITEMID_ROOT || itemid == VSITEMID_SELECTION || itemid == VSITEMID_NIL ||
		   dwDelItemOp != DELITEMOP_RemoveFromProject)
			return E_INVALIDARG;

		CHierNode node = VSITEMID2Node(itemid);
		if(!node)
			return E_INVALIDARG;

		if(CFileNode fnode = cast(CFileNode) node)
			if(HRESULT hr = fnode.CloseDoc(SLNSAVEOPT_PromptSave))
				return hr;

		return node.GetParent().Delete(node, this);
	}

	// IVsHierarchy
	override int Close()
	{
		mixin(LogCallMix);
		if(int rc = super.Close())
			return rc;
		return S_OK;
	}
        
	override int GetGuidProperty(in VSITEMID itemid, in VSHPROPID propid, GUID* pguid)
	{
		mixin(LogCallMix);

		if(itemid == VSITEMID_ROOT)
		{
			switch(propid)
			{
			case VSHPROPID_ProjectIDGuid:
				*pguid = mProjectGUID;
				return S_OK;
			case VSHPROPID_TypeGuid:
				*pguid = g_projectFactoryCLSID;
				return S_OK;
			default:
				break;
			}
		}
		return super.GetGuidProperty(itemid, propid, pguid);
	}
        
	/*override*/ int SetGuidProperty(in VSITEMID itemid, in VSHPROPID propid, in GUID* rguid)
	{
		mixin(LogCallMix2);

		if(propid != VSHPROPID_ProjectIDGuid)
			return returnError(E_NOTIMPL);
		if(itemid != VSITEMID_ROOT)
			return returnError(E_INVALIDARG);
		mProjectGUID = *rguid;
		return S_OK;
	}
        
	override int GetProperty(in VSITEMID itemid, in VSHPROPID propid, VARIANT* var)
	{
		//mixin(LogCallMix);

		if(super.GetProperty(itemid, propid, var) == S_OK)
			return S_OK;
		if(itemid != VSITEMID_ROOT)
		{
			logCall("Getting unknown property %d for item %d!", propid, itemid);
			return returnError(DISP_E_MEMBERNOTFOUND);
		}

		switch(propid)
		{
		case VSHPROPID_TypeName:
			var.vt = VT_BSTR;
			var.bstrVal = allocBSTR("typename");
			break;
		case VSHPROPID_SaveName: 
			var.vt = VT_BSTR;
			var.bstrVal = allocBSTR(mFilename);
			break;

		case VSHPROPID_ProductBrandName:
			var.vt = VT_BSTR;
			var.bstrVal = allocBSTR("VisualD");
			break;

		case VSHPROPID_BrowseObject:
			var.vt = VT_DISPATCH;
			return QueryInterface(&IDispatch.iid, cast(void **)&var.pdispVal);

		case VSHPROPID_ExtObject:
			var.vt = VT_DISPATCH;
			var.pdispVal = addref(mExtProject);
			break;
			//return DISP_E_MEMBERNOTFOUND; 

		case VSHPROPID_ProjectDir:
		    // IsNonSearchable, HasEnumerationSideEffects
		    // 1001
		//case VSHPROPID2.EnableDataSourceWindow:
		//case VSHPROPID2.DebuggeeProcessId:
		case cast(VSHPROPID) 1001:
		default:
			logCall("Getting unknown property %d for item %d!", propid, itemid);
			return DISP_E_MEMBERNOTFOUND;
			// return returnError(E_NOTIMPL); // DISP_E_MEMBERNOTFOUND; 
		}
		return S_OK;
	}
        
	override int SetProperty(in VSITEMID itemid, in VSHPROPID propid, in VARIANT var)
	{
		mixin(LogCallMix);

		switch(propid)
		{
		case VSHPROPID_Caption:
			if(var.vt != VT_BSTR)
				return returnError(E_INVALIDARG);
			mCaption = to_string(var.bstrVal);
			break;
		default:
			if(super.SetProperty(itemid, propid, var) == S_OK)
				break;
			logCall("Setting unknown property %d on %x!", propid, itemid);
			return DISP_E_MEMBERNOTFOUND;
		}
		return S_OK;
	}
        
	// IVsGetCfgProvider 
	override int GetCfgProvider(IVsCfgProvider* pCfgProvider)
	{
		//mixin(LogCallMix);

		*pCfgProvider = addref(mConfigProvider);
		return S_OK;
	}

	// ISpecifyPropertyPages
	override int GetPages( /* [out] */ CAUUID *pPages)
	{
		// needs common properties to not open settings dialog modal
		mixin(LogCallMix);
		return PropertyPageFactory.GetCommonPages(pPages);

		// no common properties
		pPages.cElems = 0;
		pPages.pElems = null;
		return S_FALSE;
		// return GetPagesImpl(pPages);
	}

	// IVsAggregatableProject
	override int SetInnerProject( 
	    /* [in] */ IUnknown punkInner)
	{
		logCall("%S.SetInnerProject(punkInner=%s)", this, _toLog(punkInner));
		return returnError(E_NOTIMPL);
	}
        
	override int InitializeForOuter( 
	    /* [in] */ in wchar* pszFilename,
	    /* [in] */ in wchar* pszLocation,
	    /* [in] */ in wchar* pszName,
	    /* [in] */ in VSCREATEPROJFLAGS grfCreateFlags,
	    /* [in] */ in IID* iidProject,
	    /* [iid_is][out] */ void **ppvProject,
	    /* [out] */ BOOL *pfCanceled)
	{
		mixin(LogCallMix);

		return returnError(E_NOTIMPL);
	}
        
	override int OnAggregationComplete()
	{
		mixin(LogCallMix);

		return returnError(E_NOTIMPL);
	}
        
	override int GetAggregateProjectTypeGuids( 
	    /* [out] */ BSTR *pbstrProjTypeGuids)
	{
		logCall("GetAggregateProjectTypeGuids(pbstrProjTypeGuids=%s)", _toLog(pbstrProjTypeGuids));
		wstring s = GUID2wstring(g_projectFactoryCLSID);
		*pbstrProjTypeGuids = allocwBSTR(s);

		return S_OK;
	}
        
	override int SetAggregateProjectTypeGuids( 
	    /* [in] */ in wchar* lpstrProjTypeGuids)
	{
		logCall("SetAggregateProjectTypeGuids(lpstrProjTypeGuids=%s)", _toLog(lpstrProjTypeGuids));

		return returnError(E_NOTIMPL);
	}
        
	// IVsProjectFlavorCfgProvider
	override int CreateProjectFlavorCfg( 
	    /* [in] */ IVsCfg pBaseProjectCfg,
	    /* [out] */ IVsProjectFlavorCfg *ppFlavorCfg)
	{
		mixin(LogCallMix);

		return returnError(E_NOTIMPL);
	}

	// IPersist
	override int GetClassID(CLSID* pClassID)
	{
		mixin(LogCallMix2);

		*pClassID = g_projectFactoryCLSID;
		return S_OK;
	}

	// IPersistFileFormat
	override int IsDirty( 
	    /* [out] */ BOOL *pfIsDirty)
	{
		logCall("IsDirty(pfIsDirty=%s)", _toLog(pfIsDirty));
		if(CProjectNode pProjectNode = GetProjectNode())
			*pfIsDirty = pProjectNode.IsProjectFileDirty();
		else
			return E_FAIL;
		return S_OK;
	}
        
	override int InitNew( 
	    /* [in] */ in DWORD nFormatIndex)
	{
		logCall("InitNew(nFormatIndex=%s)", _toLog(nFormatIndex));
		// mixin(LogCallMix);

		return returnError(E_NOTIMPL);
	}
        
	override int Load( 
	    /* [in] */ in wchar* pszFilename,
	    /* [in] */ in DWORD grfMode,
	    /* [in] */ in BOOL fReadOnly)
	{
		mixin(LogCallMix);

		return returnError(E_NOTIMPL);
	}
        
	override int Save( 
	    /* [in] */ in wchar* pszFilename,
	    /* [in] */ in BOOL fRemember,
	    /* [in] */ in DWORD nFormatIndex)
	{
		mixin(LogCallMix);
		auto doc = createDoc();

		string filename = to_string(pszFilename);
		if(!saveXML(doc, filename))
			return returnError(E_FAIL);

		return S_OK;
	}
        
	override int SaveCompleted( 
	    /* [in] */ in wchar* pszFilename)
	{
		logCall("SaveCompleted(pszFilename=%s)", _toLog(pszFilename));

		return S_OK; //returnError(E_NOTIMPL);
	}
        
	override int GetCurFile( 
	    /* [out] */ LPOLESTR *ppszFilename,
	    /* [out] */ DWORD *pnFormatIndex)
	{
		mixin(LogCallMix);

		*ppszFilename = string2OLESTR(mFilename);
		*pnFormatIndex = 0;

		return S_OK;
	}
        
	override int GetFormatList( 
	    /* [out] */ LPOLESTR *ppszFormatList)
	{
		logCall("GetFormatList(pbstrProjTypeGuids=%s)", _toLog(ppszFormatList));

		return returnError(E_NOTIMPL);
	}

	// IVsProjectBuildSystem
	override int SetHostObject( 
	    /* [in] */ in wchar* pszTargetName,
	    /* [in] */ in wchar* pszTaskName,
	    /* [in] */ IUnknown punkHostObject)
	{
		mixin(LogCallMix);

		return returnError(E_NOTIMPL);
	}
        
	override int StartBatchEdit()
	{
		mixin(LogCallMix);

		return returnError(E_NOTIMPL);
	}
        
	override int EndBatchEdit()
	{
		mixin(LogCallMix);

		return returnError(E_NOTIMPL);
	}
        
	override int CancelBatchEdit()
	{
		mixin(LogCallMix);

		return returnError(E_NOTIMPL);
	}
        
	override int BuildTarget( 
	    /* [in] */ in wchar* pszTargetName,
	    /* [retval][out] */ VARIANT_BOOL *pbSuccess)
	{
		mixin(LogCallMix);

		return returnError(E_NOTIMPL);
	}
        
	override int GetBuildSystemKind( 
	    /* [retval][out] */ BuildSystemKindFlags *pBuildSystemKind)
	{
//		mixin(LogCallMix);

		return returnError(E_NOTIMPL);
	}

	// IVsBuildPropertyStorage
	override int GetPropertyValue( 
	    /* [in] */ in wchar* pszPropName,
	    /* [in] */ in wchar* pszConfigName,
	    /* [in] */ in PersistStorageType storage,
	    /* [retval][out] */ BSTR *pbstrPropValue)
	{
		mixin(LogCallMix);

		string prop = to_string(pszPropName);
		string value;
/+
		if(prop == "RegisterOutputPackage")
			value = "true";
+/
		if(value.length == 0)
			return DISP_E_MEMBERNOTFOUND;

		*pbstrPropValue = allocBSTR(value);
		return S_OK;
	}
        
	override int SetPropertyValue( 
	    /* [in] */ in wchar* pszPropName,
	    /* [in] */ in wchar* pszConfigName,
	    /* [in] */ in PersistStorageType storage,
	    /* [in] */ in wchar* pszPropValue)
	{
		mixin(LogCallMix);

		return returnError(E_NOTIMPL);
	}
        
	override int RemoveProperty( 
	    /* [in] */ in wchar* pszPropName,
	    /* [in] */ in wchar* pszConfigName,
	    /* [in] */ in PersistStorageType storage)
	{
		mixin(LogCallMix);

		return returnError(E_NOTIMPL);
	}
        
	override int GetItemAttribute( 
	    /* [in] */ in VSITEMID item,
	    /* [in] */ in wchar* pszAttributeName,
	    /* [out] */ BSTR *pbstrAttributeValue)
	{
		mixin(LogCallMix);

		return returnError(E_NOTIMPL);
	}
        
	override int SetItemAttribute( 
	    /* [in] */ in VSITEMID item,
	    /* [in] */ in wchar* pszAttributeName,
	    /* [in] */ in wchar* pszAttributeValue)
	{
		mixin(LogCallMix);

		return returnError(E_NOTIMPL);
	}

	// IVsComponentUser
	override int AddComponent( 
	    /* [in] */ in VSADDCOMPOPERATION dwAddCompOperation,
	    /* [in] */ in ULONG cComponents,
	    /* [size_is][in] */ PVSCOMPONENTSELECTORDATA *rgpcsdComponents,
	    /* [in] */ in HWND hwndPickerDlg,
	    /* [retval][out] */ VSADDCOMPRESULT *pResult)
	{
		mixin(LogCallMix);

		return returnError(E_NOTIMPL);
	}

	// IVsDependencyProvider
	override int EnumDependencies( 
	    /* [out] */ IVsEnumDependencies *ppIVsEnumDependencies)
	{
		mixin(LogCallMix);

		return returnError(E_NOTIMPL);
	}
        
	override int OpenDependency( 
	    /* [in] */ in wchar* szDependencyCanonicalName,
	    /* [out] */ IVsDependency *ppIVsDependency)
	{
		mixin(LogCallMix);

		return returnError(E_NOTIMPL);
	}

	// IVsProjectSpecialFiles
	override int GetFile( 
	    /* [in] */ in PSFFILEID fileID,
	    /* [in] */ in PSFFLAGS grfFlags,
	    /* [out] */ VSITEMID *pitemid,
	    /* [out] */ BSTR *pbstrFilename)
	{
		mixin(LogCallMix);

		return returnError(E_NOTIMPL);
	}

	// IVsParentProject 
	override int OpenChildren()
	{
		mixin(LogCallMix);

		return returnError(E_NOTIMPL);
	}

	override int CloseChildren()
	{
		mixin(LogCallMix);

		return returnError(E_NOTIMPL);
	}

	// CVsHierarchy
	HRESULT QueryStatusSelection(in GUID *pguidCmdGroup,
				     in ULONG cCmds, OLECMD *prgCmds, OLECMDTEXT *pCmdText,
				     ref CHierNode[] rgSelection, 
				     bool bIsHierCmd)// TRUE if cmd originated via CVSUiHierarchy::ExecCommand
	{
		assert(pguidCmdGroup);
		assert(prgCmds);
		assert(cCmds == 1);

		HRESULT hr = S_OK;
		bool fHandled = false;
		bool fSupported = false;
		bool fEnabled = false;
		bool fInvisible = false;
		bool fLatched = false;
		OLECMD *Cmd = prgCmds;

		if (*pguidCmdGroup == CMDSETID_StandardCommandSet97)
		{
			// NOTE: We only want to support Cut/Copy/Paste/Delete/Rename commands
			// if focus is in the project window. This means that we should only
			// support these commands if they are dispatched via IVsUIHierarchy
			// interface and not if they are dispatch through IOleCommandTarget
			// during the command routing to the active project/hierarchy.
			if(!bIsHierCmd)
			{
				switch(Cmd.cmdID)
				{
				case cmdidCut:
				case cmdidCopy:
				case cmdidPaste:
				case cmdidRename:
					return OLECMDERR_E_NOTSUPPORTED;
				default:
					break;
				}
			}

			switch(Cmd.cmdID)
			{
				// Forward the following commands to the project node whenever our project is 
				// the active project.
			case cmdidAddNewItem:
			case cmdidAddExistingItem:

			case cmdidBuildSel:
			case cmdidRebuildSel:
			case cmdidCleanSel:
			case cmdidCancelBuild:

			case cmdidProjectSettings:
			case cmdidBuildSln:
			case cmdidUnloadProject:
			case cmdidSetStartupProject:
				return GetProjectNode().QueryStatus(pguidCmdGroup, cCmds, prgCmds, pCmdText);
			default:
				break;
			}
		}
		else if(*pguidCmdGroup == CMDSETID_StandardCommandSet2K)
		{
			switch(Cmd.cmdID)
			{
			case cmdidBuildOnlyProject:
			case cmdidRebuildOnlyProject:
			case cmdidCleanOnlyProject:
				return GetProjectNode().QueryStatus(pguidCmdGroup, cCmds, prgCmds, pCmdText);
			default:
				break;
			}
		}
		// Node commands 
		if (!fHandled)
		{
			fHandled = true;
			OLECMD cmdTemp;
			cmdTemp.cmdID = Cmd.cmdID;

			fSupported = false;
			fEnabled = true;
			fInvisible = false;
			fLatched = true;

			foreach (pNode; rgSelection)
			{
				cmdTemp.cmdf = 0;
				hr = pNode.QueryStatus(pguidCmdGroup, 1, &cmdTemp, pCmdText);

				if (SUCCEEDED(hr))
				{
					//
					// cmd is supported iff any node supports cmd
					// cmd is enabled iff all nodes enable cmd
					// cmd is invisible iff any node sets invisibility
					// cmd is latched only if all are latched.
					fSupported  =   fSupported || (cmdTemp.cmdf & OLECMDF_SUPPORTED);
					fEnabled    =   fEnabled   && (cmdTemp.cmdf & OLECMDF_ENABLED);
					fInvisible  =   fInvisible || (cmdTemp.cmdf & OLECMDF_INVISIBLE);
					fLatched    =   fLatched   && (cmdTemp.cmdf & OLECMDF_LATCHED);

					//NOTE: Currently no commands use NINCHED
					assert(!(cmdTemp.cmdf & OLECMDF_NINCHED));
				}

				// optimization
				if (!fSupported || fInvisible)
					break;
			}
		}

		if (SUCCEEDED(hr) && fSupported)
		{
			Cmd.cmdf = OLECMDF_SUPPORTED;

			if (fEnabled)
				Cmd.cmdf |= OLECMDF_ENABLED;
			if (fInvisible)
				Cmd.cmdf |= OLECMDF_INVISIBLE;
			if (fLatched)
				Cmd.cmdf |= OLECMDF_LATCHED;
		}

		return hr;
	}

	// IVsGlobalsCallback
	override int WriteVariablesToData( 
		/* [in] */ in wchar* pVariableName,
		/* [in] */ in VARIANT *varData)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int ReadData(/* [in] */ dte.Globals pGlobals)
	{
		logCall("%s.ReadData(pGlobals=%s)", this, _toLog(pGlobals));
		return returnError(E_NOTIMPL);
	}

	override int ClearVariables()
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int VariableChanged()
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int CanModifySource()
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int GetParent(IDispatch *ppOut)
	{
		logCall("%s.GetParent()", this);
		return returnError(E_NOTIMPL);
	}


	// IPerPropertyBrowsing
	override int GetDisplayString( 
		/* [in] */ in DISPID dispID,
		/* [out] */ BSTR *pBstr)
	{
		logCall("%s.GetDisplayString(dispID=%s, pBstr=%s)", this, _toLog(dispID), _toLog(pBstr));
		return returnError(E_NOTIMPL);
	}

	override int MapPropertyToPage( 
		/* [in] */ in DISPID dispID,
		/* [out] */ CLSID *pClsid)
	{
		mixin(LogCallMix);

		*pClsid = g_GeneralPropertyPage;
		return S_OK;
		//return returnError(E_NOTIMPL);
	}

	override int GetPredefinedStrings( 
		/* [in] */ in DISPID dispID,
		/* [out] */ CALPOLESTR *pCaStringsOut,
		/* [out] */ CADWORD *pCaCookiesOut)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int GetPredefinedValue( 
		/* [in] */ in DISPID dispID,
		/* [in] */ in DWORD dwCookie,
		/* [out] */ VARIANT *pVarOut)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	///////////////////////////////////////////////////////////////////////
	// IVsHierarchyDropDataSource
	override int GetDropInfo( 
		/* [out] */ DWORD *pdwOKEffects,
		/* [out] */ IDataObject *ppDataObject,
		/* [out] */ IDropSource *ppDropSource)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int OnDropNotify( 
		/* [in] */ in BOOL fDropped,
		/* [in] */ in DWORD dwEffects)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	// IVsHierarchyDropDataSource2
	override int OnBeforeDropNotify( 
		/* [in] */ IDataObject pDataObject,
		/* [in] */ in DWORD dwEffect,
		/* [retval][out] */ BOOL *pfCancelDrop)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	// IVsHierarchyDropDataTarget
	override int DragEnter( 
		/* [in] */ IDataObject pDataObject,
		/* [in] */ in DWORD grfKeyState,
		/* [in] */ in VSITEMID itemid,
		/* [out][in] */ DWORD *pdwEffect)
	{
		mixin(LogCallMix);

		*pdwEffect = DROPEFFECT_NONE;
		if (mfDragSource)
			return S_OK;

		if(HRESULT hr = QueryDropDataType(pDataObject))
			return hr;

		return QueryDropEffect(mDDT, grfKeyState, pdwEffect);
	}

	override int DragOver( 
		/* [in] */ in DWORD grfKeyState,
		/* [in] */ in VSITEMID itemid,
		/* [out][in] */ DWORD *pdwEffect)
	{
		mixin(LogCallMix);
		return QueryDropEffect(mDDT, grfKeyState, pdwEffect);
	}

	override int DragLeave()
	{
		mixin(LogCallMix);
		mDDT = DropDataType.DDT_NONE;
		return S_OK;
	}

	override int Drop( 
		/* [in] */ IDataObject pDataObject,
		/* [in] */ in DWORD grfKeyState,
		/* [in] */ in VSITEMID itemid,
		/* [out][in] */ DWORD *pdwEffect)
	{
		mixin(LogCallMix);

		if (!pDataObject)
			return E_INVALIDARG;
		if (!pdwEffect)
			return E_POINTER;
		*pdwEffect = DROPEFFECT_NONE;

		HRESULT hr = S_OK;
		if (mfDragSource) 
			return S_OK;

		DropDataType ddt;
		hr = ProcessSelectionDataObject(
			/* [in]  IDataObject* pDataObject*/ pDataObject, 
			/* [in]  DWORD        grfKeyState*/ grfKeyState,
			/* [out] DropDataType*           */ &ddt);

		// We need to report our own errors.
		if(FAILED(hr) && hr != E_UNEXPECTED && hr != OLEERR.E_PROMPTSAVECANCELLED)
		{
			UtilReportErrorInfo(hr);
		}

		// If it is a drop from windows and we get any kind of error we return S_FALSE and dropeffect none. This
		// prevents bogus messages from the shell from being displayed
		if(FAILED(hr) && ddt == DropDataType.DDT_SHELL)
		{
			hr = S_FALSE;
		}

		if (hr == S_OK)
			QueryDropEffect(ddt, grfKeyState, pdwEffect);

		return hr;
	}

	enum DropDataType //Drop types
	{
		DDT_NONE,
		DDT_SHELL,
		DDT_VSSTG,
		DDT_VSREF
	};

	const ushort CF_HDROP = 15; // winuser.h

	int QueryDropDataType(IDataObject pDataObject)
	{
		mDDT = DropDataType.DDT_NONE;

		// known formats include File Drops (as from WindowsExplorer),
		// VSProject Reference Items and VSProject Storage Items.
		FORMATETC fmtetc, fmtetcRef, fmtetcStg;

		fmtetc.cfFormat = CF_HDROP;
		fmtetc.ptd = null;
		fmtetc.dwAspect = DVASPECT_CONTENT;
		fmtetc.lindex = -1;
		fmtetc.tymed = TYMED_HGLOBAL;

		fmtetcRef.cfFormat = cast(CLIPFORMAT) RegisterClipboardFormatW("CF_VSREFPROJECTITEMS"w.ptr);
		fmtetcRef.ptd = null;
		fmtetcRef.dwAspect = DVASPECT_CONTENT;
		fmtetcRef.lindex = -1;
		fmtetcRef.tymed = TYMED_HGLOBAL;

		fmtetcStg.cfFormat = cast(CLIPFORMAT) RegisterClipboardFormatW("CF_VSSTGPROJECTITEMS"w.ptr);
		fmtetcStg.ptd = null;
		fmtetcStg.dwAspect = DVASPECT_CONTENT;
		fmtetcStg.lindex = -1;
		fmtetcStg.tymed = TYMED_HGLOBAL;

		if (pDataObject.QueryGetData(&fmtetc) == S_OK)
		{
			mDDT = DropDataType.DDT_SHELL;
			return S_OK;
		}
		if (pDataObject.QueryGetData(&fmtetcRef) == S_OK)
		{
			// Data is from a Ref-based project.
			mDDT = DropDataType.DDT_VSREF;
			return S_OK;
		}
		if (pDataObject.QueryGetData(&fmtetcStg) == S_OK)
		{
			// Data is from a Storage-based project.
			mDDT = DropDataType.DDT_VSSTG;
			return S_OK;
		}

		return S_FALSE;
	}

	int QueryDropEffect(
		/* [in]  */  DropDataType ddt,
		/* [in]  */  DWORD        grfKeyState,
		/* [out] */  DWORD *      pdwEffects)
	{
		*pdwEffects = DROPEFFECT_NONE;

		HRESULT hr = S_OK;

		// We are reference-based project so we should perform as follow:
		// for shell and physical items:
		//  NO MODIFIER - LINK
		//  SHIFT DRAG - NO DROP
		//  CTRL DRAG - NO DROP
		//  CTRL-SHIFT DRAG - LINK
		// for reference/link items
		//  NO MODIFIER - MOVE
		//  SHIFT DRAG - MOVE
		//  CTRL DRAG - COPY
		//  CTRL-SHIFT DRAG - LINK

		if(ddt != DropDataType.DDT_SHELL && ddt != DropDataType.DDT_VSREF && ddt != DropDataType.DDT_VSSTG)
			return S_FALSE;

		switch (ddt)
		{
		case DropDataType.DDT_SHELL:
		case DropDataType.DDT_VSSTG:

			// CTRL-SHIFT
			if((grfKeyState & MK_CONTROL) && (grfKeyState & MK_SHIFT))
			{
				*pdwEffects = DROPEFFECT_LINK;
				return S_OK;
			}
			// CTRL
			if(grfKeyState & MK_CONTROL)
				return S_FALSE;

			// SHIFT
			if(grfKeyState & MK_SHIFT)
				return S_FALSE;

			// no modifier
			*pdwEffects = DROPEFFECT_LINK;
			return S_OK;

		case DropDataType.DDT_VSREF:
			// CTRL-SHIFT
			if((grfKeyState & MK_CONTROL) && (grfKeyState & MK_SHIFT))
			{
				*pdwEffects = DROPEFFECT_LINK;
				return S_OK;
			}
			// CTRL
			if(grfKeyState & MK_CONTROL)
			{
				*pdwEffects = DROPEFFECT_COPY;
				return S_OK;
			}

			// SHIFT
			if(grfKeyState & MK_SHIFT)
			{
				*pdwEffects = DROPEFFECT_MOVE;
				return S_OK;
			}

			// no modifier
			*pdwEffects = DROPEFFECT_MOVE;
			return S_OK;

		default:
			return S_FALSE;
		}

		return S_FALSE;
	}

	HRESULT ProcessSelectionDataObject(
		/* [in]  */ IDataObject   pDataObject, 
		/* [in]  */ DWORD         grfKeyState,
		/* [out] */ DropDataType* pddt)
	{
		HRESULT hr = S_OK;
		if (pddt)
			*pddt = DropDataType.DDT_NONE;

		CProjectNode pProjectNode = GetProjectNode();

		FORMATETC fmtetc;
		STGMEDIUM stgmedium;
		HANDLE hDropInfo = null;

		int numFiles = 0;
		wchar[MAX_PATH+1] szMoniker;

		DropDataType ddt = DropDataType.DDT_NONE;
		BOOL fItemProcessed = FALSE;

		// try HDROP
		fmtetc.cfFormat = CF_HDROP;
		fmtetc.ptd = null;
		fmtetc.dwAspect = DVASPECT_CONTENT;
		fmtetc.lindex = -1;
		fmtetc.tymed = TYMED_HGLOBAL;

		if(pDataObject.QueryGetData(&fmtetc) != S_OK ||
		   FAILED(pDataObject.GetData(&fmtetc, &stgmedium)) ||
		   stgmedium.tymed != TYMED_HGLOBAL || !stgmedium.hGlobal)
			goto AttemptVSRefFormat;

		hDropInfo = stgmedium.hGlobal;

		// try shell format here
		ddt = DropDataType.DDT_SHELL;
		numFiles = .DragQueryFileW(hDropInfo, 0xFFFFFFFF, null, 0);
		for (int iFile = 0; iFile < numFiles; iFile++)
		{
			UINT uiRet = .DragQueryFileW(hDropInfo, iFile, szMoniker.ptr, _MAX_PATH);
			if (!uiRet || uiRet >= _MAX_PATH)
			{
				hr = E_OUTOFMEMORY; // HRESULT_FROM_WIN32(ERROR_INSUFFICIENT_BUFFER);
				continue;
			}
			szMoniker[_MAX_PATH] = 0;
			string filename = to_string(szMoniker.ptr);

			// Is full path returned
			if (exists(filename))
			{
				VSADDRESULT vsaddresult = ADDRESULT_Failure;
				wchar* wfilename = _toUTF16z(filename);
				HRESULT hrTemp = pProjectNode.GetCVsHierarchy().AddItemSpecific(pProjectNode,
					/* [in]  VSADDITEMOPERATION dwAddItemOperation */ VSADDITEMOP_OPENFILE,
					/* [in]  LPCOLESTR pszItemName                 */ null,
					/* [in]  DWORD cFilesToOpen                    */ 1,
					/* [in]  LPCOLESTR rgpszFilesToOpen[]          */ &wfilename,
					/* [in]  HWND hwndDlg                          */ null,
					/* [in]  VSSPECIFICEDITORFLAGS grfEditorFlags  */ cast(VSSPECIFICEDITORFLAGS) 0,
					/* [in]  REFGUID               rguidEditorType */ &GUID_NULL,
					/* [in]  LPCOLESTR             pszPhysicalView */ null,
					/* [in]  REFGUID               rguidLogicalView*/ &GUID_NULL,
					/* [out] VSADDRESULT *pResult                  */ &vsaddresult);
				if ( (hrTemp == E_ABORT) || (hrTemp == OLEERR.E_PROMPTSAVECANCELLED) || (vsaddresult == ADDRESULT_Cancel) )
				{
					hr = OLEERR.E_PROMPTSAVECANCELLED;
					goto Error;
				}
				if (FAILED(hrTemp))
				{
					hr = hrTemp;
					continue;
				}
				fItemProcessed = TRUE;
			}
		}
		goto Error;

AttemptVSRefFormat:
		fmtetc.cfFormat = cast(CLIPFORMAT) RegisterClipboardFormatW("CF_VSREFPROJECTITEMS"w.ptr);
		fmtetc.ptd = null;
		fmtetc.dwAspect = DVASPECT_CONTENT;
		fmtetc.lindex = -1;
		fmtetc.tymed = TYMED_HGLOBAL;

		if(pDataObject.QueryGetData(&fmtetc) != S_OK ||
		   pDataObject.GetData(&fmtetc, &stgmedium) != S_OK ||
		   stgmedium.tymed != TYMED_HGLOBAL || !stgmedium.hGlobal)
			goto AttemptVSStgFormat;

		hDropInfo = stgmedium.hGlobal;
		ddt = DropDataType.DDT_VSREF;
		goto AddFiles;

AttemptVSStgFormat:
		fmtetc.cfFormat = cast(CLIPFORMAT) RegisterClipboardFormatW("CF_VSSTGPROJECTITEMS"w.ptr);
		fmtetc.ptd = null;
		fmtetc.dwAspect = DVASPECT_CONTENT;
		fmtetc.lindex = -1;
		fmtetc.tymed = TYMED_HGLOBAL;

		if(pDataObject.QueryGetData(&fmtetc) != S_OK ||
		   pDataObject.GetData(&fmtetc, &stgmedium) != S_OK ||
		   stgmedium.tymed != TYMED_HGLOBAL || !stgmedium.hGlobal)
			goto Error;
		
		hDropInfo = stgmedium.hGlobal;
		ddt = DropDataType.DDT_VSSTG;

AddFiles:
		{
			IVsSolution srpIVsSolution = queryService!(IVsSolution);
			if(!srpIVsSolution)
				goto Error;

			// Note that we do NOT use ::DragQueryFile as this function will 
			// NOT work with unicode strings on win9x - even
			// with the unicode wrappers - and the projitem ref format is in unicode
			string[] rgSrcFiles;
			numFiles = UtilGetFilesFromPROJITEMDrop(hDropInfo, rgSrcFiles);
			for(int iFile = 0; iFile < numFiles; iFile++)
			{
				HRESULT hrTemp;
				VSITEMID itemidLoc;
				IVsHierarchy srpIVsHierarchy;
				scope(exit) release(srpIVsHierarchy);

				hrTemp = srpIVsSolution.GetItemOfProjref(_toUTF16z(rgSrcFiles[iFile]), &srpIVsHierarchy, &itemidLoc, null, null);
				if(hrTemp == E_ABORT || hrTemp == OLEERR.E_PROMPTSAVECANCELLED)
				{
					hr = OLEERR.E_PROMPTSAVECANCELLED;
					goto Error;
				}
				if (FAILED(hrTemp))
				{
					hr = hrTemp;
					continue;
				}
				if (srpIVsHierarchy is null)
				{
					hr = E_UNEXPECTED;
					continue;
				}

				// If this is a virtual item, we skip it
				GUID typeGuid;
				hrTemp = srpIVsHierarchy.GetGuidProperty(itemidLoc, VSHPROPID_TypeGuid, &typeGuid);
				if(SUCCEEDED(hrTemp) && typeGuid != GUID_ItemType_PhysicalFile)
				{
					hr = E_FAIL;
					continue;
				}
				if(hrTemp == E_ABORT || hrTemp == OLEERR.E_PROMPTSAVECANCELLED)
				{
					hr = OLEERR.E_PROMPTSAVECANCELLED;
					goto Error;
				}


				IVsProject srpIVsProject;
				scope(exit) release(srpIVsProject);

				hrTemp = srpIVsHierarchy.QueryInterface(&IVsProject.iid, cast(void **)&srpIVsProject);
				if(FAILED(hrTemp))
				{
					hr = hrTemp;
					continue;
				}
				if(srpIVsProject is null)
				{
					hr = E_UNEXPECTED;
					continue;
				}

				BSTR cbstrMoniker;
				hrTemp = srpIVsProject.GetMkDocument(itemidLoc, &cbstrMoniker);
				if (FAILED(hrTemp))
				{
					hr = hrTemp;
					continue;
				}
				string filename = detachBSTR(cbstrMoniker);
				wchar* wfilename = _toUTF16z(filename);
				VSADDRESULT vsaddresult = ADDRESULT_Failure;
				hrTemp = pProjectNode.GetCVsHierarchy().AddItemSpecific(pProjectNode,
					/* [in]  VSADDITEMOPERATION dwAddItemOperation */ VSADDITEMOP_OPENFILE,
					/* [in]  LPCOLESTR pszItemName                 */ null,
					/* [in]  DWORD cFilesToOpen                    */ 1,
					/* [in]  LPCOLESTR rgpszFilesToOpen[]          */ &wfilename,
					/* [in]  HWND hwndDlg                          */ null,
					/* [in]  VSSPECIFICEDITORFLAGS grfEditorFlags  */ cast(VSSPECIFICEDITORFLAGS) 0,
					/* [in]  REFGUID               rguidEditorType */ &GUID_NULL,
					/* [in]  LPCOLESTR             pszPhysicalView */ null,
					/* [in]  REFGUID               rguidLogicalView*/ &GUID_NULL,
					/* [out] VSADDRESULT *pResult                  */ &vsaddresult);
				if (hrTemp == E_ABORT || hrTemp == OLEERR.E_PROMPTSAVECANCELLED || vsaddresult == ADDRESULT_Cancel)
				{
					hr = OLEERR.E_PROMPTSAVECANCELLED;
					goto Error;
				}
				if (FAILED(hrTemp))
				{
					hr = hrTemp;
					continue;
				}
				fItemProcessed = TRUE;
			}
		}

Error:

		if (hDropInfo)
			.GlobalFree(hDropInfo);

		if(FAILED(hr))
			return hr;

		if (!fItemProcessed || ddt == DropDataType.DDT_NONE)
			return S_FALSE;

		if (pddt)
			*pddt = ddt;

		return S_OK;
	}


	//////////////////////////////////////////////////////////////

	dte.ConfigurationManager getConfigurationManager()
	{
		dte.ConfigurationManager mgr;
		if(IVsExtensibility3 ext = queryService!(dte.IVsExtensibility, IVsExtensibility3))
		{
			IUnknown obj;
			if(ext.GetConfigMgr(this, VSITEMID_ROOT, &obj) == S_OK)
			{
				if (obj.QueryInterface(&dte.ConfigurationManager.iid, cast(void**) &mgr) == S_OK)
					assert(mgr);
				obj.Release();
			}
			ext.Release();
		}
		return mgr;
	}

	static xml.Document readXML(string fileName)
	{
		try
		{
			string text = cast(string) read(fileName);
			size_t decidx = 0;
			if(decode(text, decidx) == 0xfeff)
				text = text[decidx..$];

			xml.Document doc = xml.readDocument(text);
			return doc;
		}
		catch(xml.RecodeException rc)
		{
			string msg = rc.toString();
			logCall(msg);
		} 
		catch(xml.XmlException rc)
		{
			string msg = rc.toString();
			logCall(msg);
		}	
		return null;
	}

	bool parseXML()
	{
		string fileName = toUTF8(mFilename);
		mDoc = readXML(fileName);
		if(!mDoc)
			return false;

		string projectName = getName(getBaseName(fileName));
		CProjectNode root = new CProjectNode(fileName, this);
		xml.Element[] propItems = xml.elementsById(xml.getRoot(mDoc), "Folder");
		foreach(item; propItems)
		{
			projectName = xml.getAttribute(item, "name");
			parseContainer(root, item);
		}
		root.SetName(projectName);

		xml.Element[] cfgItems = xml.elementsById(xml.getRoot(mDoc), "Config");
		foreach(cfg; cfgItems)
		{
			Config config = mConfigProvider.addConfig(xml.getAttribute(cfg, "name"));
			config.GetProjectOptions().readXML(cfg);
		}

		SetRootNode(root);
		return true;
	}

	void parseContainer(CHierContainer cont, xml.Element item)
	{
		xml.Element[] folderItems = xml.elementsById(item, "Folder");
		foreach(folder; folderItems)
		{
			string name = xml.getAttribute(folder, "name");
			CHierContainer node = new CFolderNode(name);
			cont.AddTail(node);
			parseContainer(node, folder);
		}

		xml.Element[] fileItems = xml.elementsById(item, "File");
		foreach(file; fileItems)
		{
			string fileName = xml.getAttribute(file, "path");
			CFileNode node = new CFileNode(fileName);
			node.SetTool(xml.getAttribute(file, "tool"));
			node.SetDependencies(xml.getAttribute(file, "dependencies"));
			node.SetOutFile(xml.getAttribute(file, "outfile"));
			node.SetCustomCmd(xml.getAttribute(file, "customcmd"));
			node.SetLinkOutput(xml.getAttribute(file, "linkoutput") == "true");
			cont.AddTail(node);
		}
	}

	static bool saveXML(xml.Document doc, string filename)
	{
		try
		{
			string[] result = xml.writeDocument(doc);

			string output;
			foreach(ostr; result)
				output ~= ostr ~ "\n";

			std.file.write(filename, output);
			return true;
		}
		catch(Exception e)
		{
			string msg = e.toString();
			logCall(msg);
		}
		return false;
	}

	xml.Document createDoc()
	{
		xml.Document doc = xml.newDocument("DProject");

		mConfigProvider.addConfigsToXml(doc);

		createDocHierarchy(xml.getRoot(doc), GetProjectNode());
		return doc;
	}

	static void createDocHierarchy(xml.Element elem, CHierContainer container)
	{
		auto xmlcontainer = new xml.Element("Folder");
		xml.setAttribute(xmlcontainer, "name", container.GetName());

		for(CHierNode node = container.GetHeadEx(false); node; node = node.GetNext(false))
		{
			if(CHierContainer cont = cast(CHierContainer) node)
				createDocHierarchy(xmlcontainer, cont);
			else if(CFileNode file = cast(CFileNode) node)
			{
				auto xmlfile = new xml.Element("File");
				
				xml.setAttribute(xmlfile, "path", file.GetFilename());

				void setAttrIfNotEmpty(string attr, string val)
				{
					if(val.length)
						xml.setAttribute(xmlfile, attr, val);
				}
				setAttrIfNotEmpty("tool", file.GetTool());
				setAttrIfNotEmpty("dependencies", file.GetDependencies());
				setAttrIfNotEmpty("outfile", file.GetOutFile());
				setAttrIfNotEmpty("customcmd", file.GetCustomCmd());
				if(file.GetLinkOutput())
					xml.setAttribute(xmlfile, "linkoutput", "true");
				xmlcontainer ~= xmlfile;
			}
		}
		elem ~= xmlcontainer;
	}

	string GetFilename() { return mFilename; }

private:
	ProjectFactory mFactory;
	string  mName;
	string  mFilename;
	string  mEditLabel;
	string  mCaption;
	GUID     mProjectGUID;
	ConfigProvider mConfigProvider;
	ExtProject mExtProject;

	bool mfDragSource;
	DropDataType mDDT;

	xml.Document mDoc;
}
