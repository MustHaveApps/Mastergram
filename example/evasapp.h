#ifndef EVASAPP_H
#define EVASAPP_H

#ifndef EFL_BETA_API_SUPPORT
#define EFL_BETA_API_SUPPORT
#endif

#ifndef EFL_EO_API_SUPPORT
#define EFL_EO_API_SUPPORT
#endif

#include <Eo.h>
#include <Efl.h>
#include <Evas.h>
#include <Ecore.h>
#include <Ecore_Evas.h>

typedef void (*appCb)(void *userData);
class EvasApp
{
public:
    EvasApp(int w, int h);
    void setup();
    void resize(int w, int h);
    int width() const{ return mw;}
    int height() const{ return mh;}
    void run();
    Ecore_Evas * ee() const{return mEcoreEvas;}
    Evas * evas() const {return mEvas;}
    Efl_VG * root() const {return mRoot;}
    void addExitCb(appCb exitcb, void *data) {mExitCb = exitcb; mExitData = data;}
    void addResizeCb(appCb resizecb, void *data) {mResizeCb = resizecb; mResizeData = data;}
public:
    int           mw;
    int           mh;
    Ecore_Evas   *mEcoreEvas;
    Evas         *mEvas;
    Efl_VG       *mRoot;
    Evas_Object  *mVg;
    Evas_Object  *mBackground;
    appCb        mResizeCb;
    void        *mResizeData;
    appCb        mExitCb;
    void        *mExitData;
};
#endif //EVASAPP_H
