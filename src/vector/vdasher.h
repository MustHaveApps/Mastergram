#ifndef VDASHER_H
#define VDASHER_H
#include "vpath.h"
class VDasher
{
 public:
    VDasher(const float *dashArray, int size);
    VPath dashed(const VPath &path);
 private:
    void moveTo(const VPointF &p);
    void lineTo(const VPointF &p);
    void cubicTo(const VPointF &cp1, const VPointF &cp2, const VPointF &e);
    void close();
private:
    struct Dash {
      float length;
      float gap;
    };
    const VDasher::Dash   *mDashArray;
    int                    mArraySize;
    VPointF               mStartPt;
    VPointF               mCurPt;
    int                    mCurrentDashIndex;
    int                    mCurrentDashLength;
    bool                   mIsCurrentOperationGap;
    float                  mDashOffset;
    VPath                 mDashedPath;
};
#endif // VDASHER_H
