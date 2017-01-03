{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE NoOverloadedStrings       #-}
{-# LANGUAGE UndecidableInstances      #-}

module Luna.IR.ToRefactor where

import Luna.Prelude hiding (String, log, nested)
import qualified Luna.Prelude as Prelude

import Luna.IR.Internal.IR
import qualified Luna.IR.Expr.Term.Named as Term
import qualified Luna.IR.Internal.LayerStore as Store
import Luna.IR.Expr.Layout.Class
import Luna.IR.Expr.Layout.ENT
import Luna.IR.Layer
import Luna.IR.Layer.Type
import Luna.IR.Layer.Model
import Luna.IR.Layer.UID
import Luna.IR.Layer.Succs
import Luna.IR.Expr.Term.Named (HasName, name)
import Luna.IR.Expr.Format
import Luna.IR.Expr.Atom
import Data.Property
import qualified Luna.Pass        as Pass
import           Luna.Pass        (Pass, Preserves, Inputs, Outputs, Events, SubPass, Uninitialized, Template, DynPass, ElemScope, KnownElemPass, elemPassDescription, genericDescription, genericDescriptionP)
import Data.TypeDesc
import Data.Event (type (//), Tag(Tag))
import qualified Data.Set as Set
import Luna.IR.Internal.LayerStore (STRef, STRefM)
import Luna.IR.Expr
import Unsafe.Coerce (unsafeCoerce)
import Luna.Pass.Manager as PM
import Data.Event as Event
import System.Log
import qualified Control.Monad.State.Dependent.Old as DepState

import qualified GHC.Prim as Prim

import Data.Reflection (Reifies)
import Luna.Pass.TH

import Type.Any (AnyType)

---------------------------------------
-- Some important utils





type family RTC (c :: Constraint) :: Constraint where
    RTC () = ()
    RTC (t1,t2) = (RTC t1, (RTC t2, ()))
    RTC (t1,t2,t3) = (RTC t1, (RTC t2, (RTC t3, ())))
    RTC (t1,t2,t3,t4) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, ()))))
    RTC (t1,t2,t3,t4,t5) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, ())))))
    RTC (t1,t2,t3,t4,t5,t6) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, ()))))))
    RTC (t1,t2,t3,t4,t5,t6,t7) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, ())))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, ()))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, ())))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, ()))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, ())))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, ()))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, ())))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, ()))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, ())))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, ()))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, ())))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, ()))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, ())))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, ()))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, ())))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, ()))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, ())))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, ()))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, ())))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, ()))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, ())))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, ()))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, ())))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, ()))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, ())))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, ()))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, ())))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, ()))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, ())))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, ()))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, ())))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37,t38) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, (RTC t38, ()))))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37,t38,t39) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, (RTC t38, (RTC t39, ())))))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37,t38,t39,t40) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, (RTC t38, (RTC t39, (RTC t40, ()))))))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37,t38,t39,t40,t41) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, (RTC t38, (RTC t39, (RTC t40, (RTC t41, ())))))))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37,t38,t39,t40,t41,t42) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, (RTC t38, (RTC t39, (RTC t40, (RTC t41, (RTC t42, ()))))))))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37,t38,t39,t40,t41,t42,t43) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, (RTC t38, (RTC t39, (RTC t40, (RTC t41, (RTC t42, (RTC t43, ())))))))))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37,t38,t39,t40,t41,t42,t43,t44) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, (RTC t38, (RTC t39, (RTC t40, (RTC t41, (RTC t42, (RTC t43, (RTC t44, ()))))))))))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37,t38,t39,t40,t41,t42,t43,t44,t45) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, (RTC t38, (RTC t39, (RTC t40, (RTC t41, (RTC t42, (RTC t43, (RTC t44, (RTC t45, ())))))))))))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37,t38,t39,t40,t41,t42,t43,t44,t45,t46) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, (RTC t38, (RTC t39, (RTC t40, (RTC t41, (RTC t42, (RTC t43, (RTC t44, (RTC t45, (RTC t46, ()))))))))))))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37,t38,t39,t40,t41,t42,t43,t44,t45,t46,t47) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, (RTC t38, (RTC t39, (RTC t40, (RTC t41, (RTC t42, (RTC t43, (RTC t44, (RTC t45, (RTC t46, (RTC t47, ())))))))))))))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37,t38,t39,t40,t41,t42,t43,t44,t45,t46,t47,t48) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, (RTC t38, (RTC t39, (RTC t40, (RTC t41, (RTC t42, (RTC t43, (RTC t44, (RTC t45, (RTC t46, (RTC t47, (RTC t48, ()))))))))))))))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37,t38,t39,t40,t41,t42,t43,t44,t45,t46,t47,t48,t49) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, (RTC t38, (RTC t39, (RTC t40, (RTC t41, (RTC t42, (RTC t43, (RTC t44, (RTC t45, (RTC t46, (RTC t47, (RTC t48, (RTC t49, ())))))))))))))))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37,t38,t39,t40,t41,t42,t43,t44,t45,t46,t47,t48,t49,t50) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, (RTC t38, (RTC t39, (RTC t40, (RTC t41, (RTC t42, (RTC t43, (RTC t44, (RTC t45, (RTC t46, (RTC t47, (RTC t48, (RTC t49, (RTC t50, ()))))))))))))))))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37,t38,t39,t40,t41,t42,t43,t44,t45,t46,t47,t48,t49,t50,t51) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, (RTC t38, (RTC t39, (RTC t40, (RTC t41, (RTC t42, (RTC t43, (RTC t44, (RTC t45, (RTC t46, (RTC t47, (RTC t48, (RTC t49, (RTC t50, (RTC t51, ())))))))))))))))))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37,t38,t39,t40,t41,t42,t43,t44,t45,t46,t47,t48,t49,t50,t51,t52) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, (RTC t38, (RTC t39, (RTC t40, (RTC t41, (RTC t42, (RTC t43, (RTC t44, (RTC t45, (RTC t46, (RTC t47, (RTC t48, (RTC t49, (RTC t50, (RTC t51, (RTC t52, ()))))))))))))))))))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37,t38,t39,t40,t41,t42,t43,t44,t45,t46,t47,t48,t49,t50,t51,t52,t53) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, (RTC t38, (RTC t39, (RTC t40, (RTC t41, (RTC t42, (RTC t43, (RTC t44, (RTC t45, (RTC t46, (RTC t47, (RTC t48, (RTC t49, (RTC t50, (RTC t51, (RTC t52, (RTC t53, ())))))))))))))))))))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37,t38,t39,t40,t41,t42,t43,t44,t45,t46,t47,t48,t49,t50,t51,t52,t53,t54) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, (RTC t38, (RTC t39, (RTC t40, (RTC t41, (RTC t42, (RTC t43, (RTC t44, (RTC t45, (RTC t46, (RTC t47, (RTC t48, (RTC t49, (RTC t50, (RTC t51, (RTC t52, (RTC t53, (RTC t54, ()))))))))))))))))))))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37,t38,t39,t40,t41,t42,t43,t44,t45,t46,t47,t48,t49,t50,t51,t52,t53,t54,t55) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, (RTC t38, (RTC t39, (RTC t40, (RTC t41, (RTC t42, (RTC t43, (RTC t44, (RTC t45, (RTC t46, (RTC t47, (RTC t48, (RTC t49, (RTC t50, (RTC t51, (RTC t52, (RTC t53, (RTC t54, (RTC t55, ())))))))))))))))))))))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37,t38,t39,t40,t41,t42,t43,t44,t45,t46,t47,t48,t49,t50,t51,t52,t53,t54,t55,t56) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, (RTC t38, (RTC t39, (RTC t40, (RTC t41, (RTC t42, (RTC t43, (RTC t44, (RTC t45, (RTC t46, (RTC t47, (RTC t48, (RTC t49, (RTC t50, (RTC t51, (RTC t52, (RTC t53, (RTC t54, (RTC t55, (RTC t56, ()))))))))))))))))))))))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37,t38,t39,t40,t41,t42,t43,t44,t45,t46,t47,t48,t49,t50,t51,t52,t53,t54,t55,t56,t57) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, (RTC t38, (RTC t39, (RTC t40, (RTC t41, (RTC t42, (RTC t43, (RTC t44, (RTC t45, (RTC t46, (RTC t47, (RTC t48, (RTC t49, (RTC t50, (RTC t51, (RTC t52, (RTC t53, (RTC t54, (RTC t55, (RTC t56, (RTC t57, ())))))))))))))))))))))))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37,t38,t39,t40,t41,t42,t43,t44,t45,t46,t47,t48,t49,t50,t51,t52,t53,t54,t55,t56,t57,t58) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, (RTC t38, (RTC t39, (RTC t40, (RTC t41, (RTC t42, (RTC t43, (RTC t44, (RTC t45, (RTC t46, (RTC t47, (RTC t48, (RTC t49, (RTC t50, (RTC t51, (RTC t52, (RTC t53, (RTC t54, (RTC t55, (RTC t56, (RTC t57, (RTC t58, ()))))))))))))))))))))))))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37,t38,t39,t40,t41,t42,t43,t44,t45,t46,t47,t48,t49,t50,t51,t52,t53,t54,t55,t56,t57,t58,t59) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, (RTC t38, (RTC t39, (RTC t40, (RTC t41, (RTC t42, (RTC t43, (RTC t44, (RTC t45, (RTC t46, (RTC t47, (RTC t48, (RTC t49, (RTC t50, (RTC t51, (RTC t52, (RTC t53, (RTC t54, (RTC t55, (RTC t56, (RTC t57, (RTC t58, (RTC t59, ())))))))))))))))))))))))))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37,t38,t39,t40,t41,t42,t43,t44,t45,t46,t47,t48,t49,t50,t51,t52,t53,t54,t55,t56,t57,t58,t59,t60) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, (RTC t38, (RTC t39, (RTC t40, (RTC t41, (RTC t42, (RTC t43, (RTC t44, (RTC t45, (RTC t46, (RTC t47, (RTC t48, (RTC t49, (RTC t50, (RTC t51, (RTC t52, (RTC t53, (RTC t54, (RTC t55, (RTC t56, (RTC t57, (RTC t58, (RTC t59, (RTC t60, ()))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37,t38,t39,t40,t41,t42,t43,t44,t45,t46,t47,t48,t49,t50,t51,t52,t53,t54,t55,t56,t57,t58,t59,t60,t61) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, (RTC t38, (RTC t39, (RTC t40, (RTC t41, (RTC t42, (RTC t43, (RTC t44, (RTC t45, (RTC t46, (RTC t47, (RTC t48, (RTC t49, (RTC t50, (RTC t51, (RTC t52, (RTC t53, (RTC t54, (RTC t55, (RTC t56, (RTC t57, (RTC t58, (RTC t59, (RTC t60, (RTC t61, ())))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))
    RTC (t1,t2,t3,t4,t5,t6,t7,t8,t9,t10,t11,t12,t13,t14,t15,t16,t17,t18,t19,t20,t21,t22,t23,t24,t25,t26,t27,t28,t29,t30,t31,t32,t33,t34,t35,t36,t37,t38,t39,t40,t41,t42,t43,t44,t45,t46,t47,t48,t49,t50,t51,t52,t53,t54,t55,t56,t57,t58,t59,t60,t61,t62) = (RTC t1, (RTC t2, (RTC t3, (RTC t4, (RTC t5, (RTC t6, (RTC t7, (RTC t8, (RTC t9, (RTC t10, (RTC t11, (RTC t12, (RTC t13, (RTC t14, (RTC t15, (RTC t16, (RTC t17, (RTC t18, (RTC t19, (RTC t20, (RTC t21, (RTC t22, (RTC t23, (RTC t24, (RTC t25, (RTC t26, (RTC t27, (RTC t28, (RTC t29, (RTC t30, (RTC t31, (RTC t32, (RTC t33, (RTC t34, (RTC t35, (RTC t36, (RTC t37, (RTC t38, (RTC t39, (RTC t40, (RTC t41, (RTC t42, (RTC t43, (RTC t44, (RTC t45, (RTC t46, (RTC t47, (RTC t48, (RTC t49, (RTC t50, (RTC t51, (RTC t52, (RTC t53, (RTC t54, (RTC t55, (RTC t56, (RTC t57, (RTC t58, (RTC t59, (RTC t60, (RTC t61, (RTC t62, ()))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))
    RTC t1 = (t1, ())


type family FilterInputs t (a :: Constraint) :: [*] where
    FilterInputs t (a,as)         = FilterInputs t a <> FilterInputs t as
    FilterInputs t (Reader t a m) = '[a]
    FilterInputs t (Editor t a m) = '[a]
    FilterInputs t a              = '[]

type family FilterOutputs t (a :: Constraint) :: [*] where
    FilterOutputs t (a,as)         = FilterOutputs t a <> FilterOutputs t as
    FilterOutputs t (Writer t a m) = '[a]
    FilterOutputs t (Editor t a m) = '[a]
    FilterOutputs t a              = '[]

type family FilterEmitters (a :: Constraint) :: [*] where
    FilterEmitters (a,as)        = FilterEmitters a <> FilterEmitters as
    FilterEmitters (Emitter e m) = '[e]
    FilterEmitters a             = '[]

type GetInputs   t c = FilterInputs   t (RTC c)
type GetOutputs  t c = FilterOutputs  t (RTC c)
type GetEmitters e   = FilterEmitters   (RTC e)

-- type Foo m = ( Readers Layer '[AnyExpr // Model, AnyExpr // Type] m
--              , Editors Net   '[AnyExprLink] m
--              , Emitter (Delete // AnyExprLink) m
--              , MonadRef m
--              )




-- type Foo m = Req m '[ Reader  // Layer  // AnyExpr // '[Model, Type]
--                     , Reader  // Net    // AnyExprLink
--                     , Emitter // Delete // AnyExprLink
--                     ]

type Req m (rs :: [*]) = (DescConstr m (Expands (Proxy rs)), MonadRef m)

-- type family Expand es ls where
--     Expand es ((l :: [k]) // ls) = es
--     Expand es ((l :: *)   // ls) = es



type family DescConstr m ls :: Constraint where
    DescConstr m '[] = ()
    DescConstr m ((Reader  // t // s) ': rs) = (Reader  t s m, DescConstr m rs)
    DescConstr m ((Writer  // t // s) ': rs) = (Writer  t s m, DescConstr m rs)
    DescConstr m ((Editor  // t // s) ': rs) = (Editor  t s m, DescConstr m rs)
    DescConstr m ((Emitter // e)      ': rs) = (Emitter e   m, DescConstr m rs)





-----------------------------------------------




type instance RefData Attr a _ = a





data Abstracted a
type instance Abstract (TypeRef s) = TypeRef (Abstracted s)




-- data ELEMSCOPE p elem
-- data ElemScope p elem
-- type instance Abstract (ElemScope c t) = ELEMSCOPE (Abstract c) (Abstract t)
--
-- type ElemSubPass p elem   = SubPass (ElemScope p elem)
-- type ElemPass    p elem m = ElemSubPass p elem m ()
--
-- proxifyElemPass :: ElemSubPass p elem m a -> (Proxy elem -> ElemSubPass p elem m a)
-- proxifyElemPass = const ; {-# INLINE proxifyElemPass #-}


-- m (m [Template (DynPass (GetPassManager m))])




-------------------------------------------
-------------------------------------------
-------------------------------------------
-------------------------------------------
-- Layer passes

type MonadPassManagerST m s = (MonadPassManager m, s ~ PrimState m)

debugPassRunning layer = withDebugBy ("Pass [" <> layer <> "]") "Running"



proxify :: a -> Proxy a
proxify _ = Proxy

-- newtype EventPass p e t m = EventPass (MonadPassManager m => PayloadData (e // t) -> Pass (ElemScope p t) m)
-- -- type    EventPass p e t m = EventPass p e t (PrimState m)
--
-- runEventPass :: forall p e t m. (KnownType p, MonadPassManager m) => EventPass p e t m -> PayloadData (e // t) -> Pass (ElemScope p t) m
-- runEventPass (EventPass f) pload = debugPassRunning (show $ getTypeDesc_ @p) $ f pload
--
-- foo :: forall p e t m. (KnownType p, MonadPassManager m, Pass.PassInit (ElemScope p t) m) => EventPass p e t m -> Pass.Describbed (Uninitialized m (Template (DynPass m)))
-- foo = Pass.describbed @(ElemScope p t) . Pass.compileTemplate . Pass.template . runEventPass


newtype EventPassDef2 p e t m = EventPassDef2 (PayloadData (e // t) -> m ())
makeWrapped ''EventPassDef2


newtype EventPassDef e t m = EventPassDef (PayloadData (e // t) -> m ())
makeWrapped ''EventPassDef

eventPassDef :: (PayloadData (e // t) -> m ()) -> EventPassDef e t m
eventPassDef = wrap' ; {-# INLINE eventPassDef #-}

runEventPassDef :: EventPassDef e t m -> (PayloadData (e // t) -> m ())
runEventPassDef = unwrap' ; {-# INLINE runEventPassDef #-}

runEventPassDef2 :: EventPassDef2 p e t m -> (PayloadData (e // t) -> m ())
runEventPassDef2 = unwrap' ; {-# INLINE runEventPassDef2 #-}



foo2 :: forall p e t m. (KnownType p, MonadPassManager m, Pass.PassInit (ElemScope p t) m)
     => EventPassDef e t (SubPass (ElemScope p t) m) -> Pass.Describbed (Uninitialized m (Template (DynPass m)))
foo2 = Pass.describbed @(ElemScope p t) . Pass.compileTemplate . Pass.template . runEventPassDef


type ElemEventPassDef e t m = EventPassDef e (Elem t) m
type ElemEventPassDef2 p e t m = EventPassDef2 p e (Elem t) m
-- makeWrapped ''ElemEventPassDef



newtype ElemEventPass p e t m = EventPass (EventPassDef e (Elem t) (SubPass (ElemScope p t) m))

-- type    AnyElemEventPass e p m = AnyElemEventPass e p (PrimState m)
newtype AnyElemEventPass p e m = AnyElemEventPass ( forall t. (MonadPassManager m, KnownType (Abstract t))
                                                 => EventPassDef e (Elem t) (SubPass (ElemScope p t) m)
                                                  )
--
-- newtype AnyElemEventPass p e m = AnyElemEventPass ( forall t. (MonadPassManager m, KnownType (Abstract t))
--                                                  => ElemEventPass p e t m
--                                                   )

type    ElemEventPass2M e t p m = ElemEventPass2 e t p (PrimState m)
newtype ElemEventPass2  e t p s = ElemEventPass2 (forall m. (MonadPassManager m, s ~ PrimState m) => ElemEventPassDef e t (SubPass (ElemScope p t) m))

runElemEventPass :: forall e p t m. (KnownType p, MonadPassManager m, KnownType (Abstract t))
                 => AnyElemEventPass p e m -> PayloadData (e // Elem t) -> Pass (ElemScope p t) m
runElemEventPass (AnyElemEventPass p) pld = debugPassRunning (show $ getTypeDesc_ @p) $ runEventPassDef p pld ; {-# INLINE runElemEventPass #-}


registerGenLayer :: (MonadPassManager m, MonadPassManager (GetRefHandler m), Pass.DataLookup (GetRefHandler m), KnownElemPass p, KnownType p)
                      => LayerDesc -> AnyElemEventPass p New (GetRefHandler m) -> m ()
registerGenLayer l p = registerLayerProto l $ prepareProto2 $ Pass.template $ runElemEventPass p ; {-# INLINE registerGenLayer #-}

registerGenLayer2 :: forall p e t m. (MonadPassManager m, MonadPassManager (GetRefHandler m), Pass.DataLookup (GetRefHandler m), KnownElemPass p, KnownType p)
                      => LayerDesc -> (forall t. KnownType (Abstract t) => ElemEventPassDef2 p e t (SubPass (ElemScope p t) (GetRefHandler m))) -> m ()
registerGenLayer2 l p = registerLayerProto l $ prepareProto2 $ Pass.template $ runEventPassDef2 p ; {-# INLINE registerGenLayer2 #-}

-- registerLayerDef :: (MonadPassManager m, MonadPassManager (GetRefHandler m), Pass.DataLookup (GetRefHandler m), KnownElemPass p, KnownType p)
--                          => LayerDesc -> (forall t. KnownType (Abstract t) => ElemEventPassDef e t (SubPass (ElemScope p t) (GetRefHandler m))) -> m ()
-- registerLayerDef l p = registerLayerProto l $ prepareProto2 $ Pass.template $ runEventPassDef p ; {-# INLINE registerLayerDef #-}

-- registerGenLayer2 :: (MonadPassManager m, MonadPassManager (GetRefHandler m), Pass.DataLookup (GetRefHandler m), KnownElemPass p, KnownType p)
--                   => LayerDesc -> ElemEventPassDef (Pass (ElemScope p) ) -> m ()
-- registerGenLayer2 l p = registerLayerProto l $ prepareProto $ Pass.template $ runEventPassDef p ; {-# INLINE registerGenLayer2 #-}


newtype GenLayerCons  p s = GenLayerCons (forall t m. (KnownType (Abstract t), MonadPassManager m, s ~ PrimState m) => (Elem t, Definition t) -> Pass (ElemScope p (Elem t)) m)
type    GenLayerConsM p m = GenLayerCons p (PrimState m)

newtype ExprLayerCons  p s = ExprLayerCons (forall l m. MonadPassManagerST m s => (Expr l, Definition (Expr l)) -> Pass (ElemScope p (Expr l)) m)
type    ExprLayerConsM p m = ExprLayerCons p (PrimState m)

runGenLayerCons :: forall p m. (KnownType p, MonadPassManager m) => GenLayerConsM p m -> forall t. KnownType (Abstract t) => (Elem t, Definition t) -> Pass (ElemScope p (Elem t)) m
runGenLayerCons (GenLayerCons f) (t, tdef) = debugPassRunning (show $ getTypeDesc_ @p) $ f (t, tdef)


-- runElemEventPass :: forall p m. (KnownType p, MonadPassManager m) => GenLayerConsM p m -> forall t. KnownType (Abstract t) => (Elem t, Definition t) -> Pass (ElemScope p (Elem t)) m
-- runElemEventPass (ElemEventPassDef (EventPassDef f)) (t, tdef) = debugPassRunning (show $ getTypeDesc_ @p) $ f (t, tdef)

runExprLayerCons :: forall p m. (KnownType p, MonadPassManager m) => ExprLayerConsM p m -> forall l. (Expr l, Definition (Expr l)) -> Pass (ElemScope p (Expr l)) m
runExprLayerCons (ExprLayerCons f) (t, tdef) = debugPassRunning (show $ getTypeDesc_ @p) $ f (t, tdef)


-- registerGenLayer :: (MonadPassManager m, MonadPassManager (GetRefHandler m), Pass.DataLookup (GetRefHandler m), KnownElemPass p, KnownType p) => LayerDesc -> GenLayerConsM p (GetRefHandler m) -> m ()
-- registerGenLayer l p = registerLayerProto l $ prepareProto $ Pass.template $ runGenLayerCons p ; {-# INLINE registerGenLayer #-}


-- registerGenLayerM :: (MonadPassManager m, MonadPassManager (GetRefHandler m), KnownElemPass p, KnownType p, Pass.DataLookup (GetRefHandler m)) => LayerDesc -> m (GenLayerConsM p (GetRefHandler m)) -> m ()
-- registerGenLayerM l p = registerGenLayer l =<< p ; {-# INLINE registerGenLayerM #-}


registerExprLayer2 :: forall p l m. (MonadPassManager m, MonadPassManager (GetRefHandler m), KnownElemPass p, KnownType p, Pass.DataLookup (GetRefHandler m)) => LayerDesc -> ExprLayerConsM p (GetRefHandler m) -> m ()
registerExprLayer2 l p = registerLayerProto l $ Pass.Proto $ \_ -> Pass.describbed @(ElemScope p (Expr l)) . Pass.compileTemplate $ Pass.template $ runExprLayerCons p ; {-# INLINE registerExprLayer2 #-}
--
registerExprLayerM2 :: (MonadPassManager m, MonadPassManager (GetRefHandler m), KnownElemPass p, KnownType p, Pass.DataLookup (GetRefHandler m)) => LayerDesc -> m (ExprLayerConsM p (GetRefHandler m)) -> m ()
registerExprLayerM2 l p = registerExprLayer2 l =<< p ; {-# INLINE registerExprLayerM2 #-}



prepareProto :: forall p m. (Logging m, Pass.DataLookup m, KnownElemPass p) => (forall s. TypeReify (Abstracted s) => Template (Pass (ElemScope p (Elem (TypeRef s))) m)) -> Pass.Proto (Pass.Describbed (Uninitialized m (Template (DynPass m))))
prepareProto p = Pass.Proto $ reifyKnownTypeT @Abstracted (prepareProto' p) . (head . view subDescs) {- we take type args here, cause we need only `t` instead of `Elem t` -} where
    prepareProto' :: forall p t m. (Logging m, KnownType (Abstract t), Pass.DataLookup m, KnownElemPass p) => Template (Pass (ElemScope p (Elem t)) m) -> Proxy t -> Pass.Describbed (Uninitialized m (Template (DynPass m)))
    prepareProto' = const . Pass.describbed @(ElemScope p (Elem t)) . Pass.compileTemplate

prepareProto2 :: forall p m. (Logging m, Pass.DataLookup m, KnownElemPass p) => (forall s. TypeReify (Abstracted s) => Template (Pass (ElemScope p (TypeRef s)) m)) -> Pass.Proto (Pass.Describbed (Uninitialized m (Template (DynPass m))))
prepareProto2 p = Pass.Proto $ reifyKnownTypeT @Abstracted (prepareProto2' p) . (head . view subDescs) {- we take type args here, cause we need only `t` instead of `Elem t` -} where
    prepareProto2' :: forall p t m. (Logging m, KnownType (Abstract t), Pass.DataLookup m, KnownElemPass p) => Template (Pass (ElemScope p t) m) -> Proxy t -> Pass.Describbed (Uninitialized m (Template (DynPass m)))
    prepareProto2' = const . Pass.describbed @(ElemScope p (Elem t)) . Pass.compileTemplate



-------------------
-- === Model === --
-------------------


initModel :: Req m '[Writer // Layer // Abstract (Elem t) // Model] => EventPassDef New (Elem t) m
initModel = eventPassDef . uncurry . flip $ writeLayer @Model ; {-# INLINE initModel #-}
makePass 'initModel

data InitModel2
initModel2 :: Req m '[Writer // Layer // Abstract (Elem t) // Model] => EventPassDef2 InitModel2 New (Elem t) m
initModel2 = wrap' . uncurry . flip $ writeLayer @Model ; {-# INLINE initModel2 #-}
makePass2 'initModel2

init1 :: (MonadPassManager m, MonadPassManager (GetRefHandler m), Pass.DataLookup (GetRefHandler m)) => m ()
-- init1 = registerGenLayer (getTypeDesc @Model) initModelPass
init1 = registerGenLayer2 (getTypeDesc @Model) initModel2

initModelPass :: AnyElemEventPass InitModel New s
initModelPass = AnyElemEventPass initModel ; {-# INLINE initModelPass #-}






-- initModel :: Req m '[Writer // Layer // Abstract (Elem t) // Model] => ElemEventPassDef InitModel New t m
-- initModel = eventPassDef . uncurry . flip $ writeLayer @Model ; {-# INLINE initModel #-}
-- makePass 'initModel
--
-- init1 :: (MonadPassManager m, MonadPassManager (GetRefHandler m), Pass.DataLookup (GetRefHandler m)) => m ()
-- init1 = registerGenLayer (getTypeDesc @Model) initModel


-----------------
-- === UID === --
-----------------

initUID :: Req m '[Writer // Layer // Abstract (Elem t) // UID] => STRefM m ID -> EventPassDef New (Elem t) m
initUID ref = eventPassDef $ \(t, tdef) -> do
    nuid <- Store.modifySTRef' ref (\i -> (i, succ i))
    writeLayer @UID nuid t
{-# INLINE initUID #-}
makePass1 'initUID

init2 :: (MonadPassManager m, MonadPassManager (GetRefHandler m), Pass.DataLookup (GetRefHandler m)) => m ()
init2 = do
    ref <- Store.newSTRef (def :: ID)
    registerGenLayer (getTypeDesc @UID) (initUIDPass ref)

initUIDPass :: STRefM m ID -> AnyElemEventPass InitUID New m
initUIDPass p = AnyElemEventPass $ initUID p ; {-# INLINE initUIDPass #-}




-------------------
-- === Succs === --
-------------------

initSuccs :: Req m '[Writer // Layer // Abstract (Elem t) // Succs] => EventPassDef New (Elem t) m
initSuccs = eventPassDef $ \(t, _) -> writeLayer @Succs mempty t ; {-# INLINE initSuccs #-}
makePass 'initSuccs

initSuccsPass :: AnyElemEventPass InitSuccs New m
initSuccsPass = AnyElemEventPass initSuccs ; {-# INLINE initSuccsPass #-}

watchSuccs :: Req m '[Editor // Layer // AnyExpr // Succs] => EventPassDef New (ExprLink' l) m
watchSuccs = EventPassDef $ \(t, (src, tgt)) -> modifyLayer_ @Succs (Set.insert $ unsafeGeneralize t) src ; {-# INLINE watchSuccs #-}
makePass 'watchSuccs

watchRemoveEdge :: Req m '[ Reader // Layer // AnyExprLink // Model
                          , Editor // Layer // AnyExpr // Succs]
                => EventPassDef Delete (ExprLink' l) m
watchRemoveEdge = EventPassDef $ \t -> do
    (src, tgt) <- readLayer @Model t
    modifyLayer_ @Succs (Set.delete $ unsafeGeneralize t) src
{-# INLINE watchRemoveEdge #-}
makePass 'watchRemoveEdge

init3 :: (MonadPassManager m, MonadPassManager (GetRefHandler m), Pass.DataLookup (GetRefHandler m)) => m ()
init3 = do
    registerGenLayer (getTypeDesc @Succs) initSuccsPass
    addEventListener (Tag [getTypeDesc @New   , getTypeDesc @(Link' AnyExpr)]) $ foo2 @WatchSuccs watchSuccs
    addEventListener (Tag [getTypeDesc @Delete, getTypeDesc @(Link' AnyExpr)]) $ foo2 @WatchRemoveEdge watchRemoveEdge





--
--
-- data WatchRemoveNode
-- type instance Inputs  Net   (ElemScope WatchRemoveNode t) = '[AnyExprLink]
-- type instance Outputs Net   (ElemScope WatchRemoveNode t) = '[AnyExprLink]
-- type instance Inputs  Layer (ElemScope WatchRemoveNode t) = '[AnyExpr // Model, AnyExpr // Type]
-- type instance Outputs Event (ElemScope WatchRemoveNode t) = '[Delete // AnyExprLink]
-- makeEventPass ''WatchRemoveNode

--
--
--
-- data WatchRemoveNode
-- type instance Req (ElemScope WatchRemoveNode t) = '[ Editor // Net // AnyExprLink
--                                                    , Input // Layer // '[Model, Type]
--                                                    , Event // Delete // AnyExprLink
--                                                    ]
-- makeEventPass ''WatchRemoveNode
--
-- watchRemoveNode :: EventPass WatchRemoveNode Delete (Expr l) s
-- watchRemoveNode = EventPass $ \t -> do
--     inps   <- symbolFields (generalize t :: SomeExpr)
--     tp     <- readLayer @Type t
--     delete tp
--     mapM_ delete inps
--
--
--
-- watchRemoveNode :: Req m '[ Editor // Net    // AnyExprLink
--                           , Input  // Layer  // '[Model, Type]
--                           , Event  // Delete // AnyExprLink
--                           ]
--                 => EventPass Delete (Expr l) m
-- watchRemoveNode = EventPass $ \t -> do
--     inps   <- symbolFields (generalize t :: SomeExpr)
--     tp     <- readLayer @Type t
--     delete tp
--     mapM_ delete inps
--
-- makeEventPass ''watchRemoveNode





watchRemoveNode2 :: ( Readers Layer '[AnyExpr // Model, AnyExpr // Type] m
                    , Editors Net   '[AnyExprLink] m
                    , Emitter (Delete // AnyExprLink) m
                    , MonadRef m
                    )
                 => EventPassDef Delete (Expr l) m
watchRemoveNode2 = EventPassDef $ \t -> do
    inps   <- symbolFields (generalize t :: SomeExpr)
    tp     <- readLayer @Type t
    delete tp
    mapM_ delete inps



data WatchRemoveNode
type instance Abstract WatchRemoveNode = WatchRemoveNode
type instance Inputs  Net   (ElemScope WatchRemoveNode t) = GetInputs  Net   (Foo AnyType)
type instance Outputs Net   (ElemScope WatchRemoveNode t) = GetOutputs Net   (Foo AnyType)
type instance Inputs  Layer (ElemScope WatchRemoveNode t) = GetInputs  Layer (Foo AnyType)
type instance Outputs Layer (ElemScope WatchRemoveNode t) = GetOutputs Layer (Foo AnyType)
type instance Inputs  Attr  (ElemScope WatchRemoveNode t) = GetInputs  Attr  (Foo AnyType)
type instance Outputs Attr  (ElemScope WatchRemoveNode t) = GetOutputs Attr  (Foo AnyType)
type instance Inputs  Event (ElemScope WatchRemoveNode t) = '[]
type instance Outputs Event (ElemScope WatchRemoveNode t) = GetEmitters (Foo AnyType)
type instance Preserves     (ElemScope WatchRemoveNode t) = '[]
instance KnownElemPass WatchRemoveNode where
    elemPassDescription = genericDescriptionP





type Foo m = Req m '[ Reader  // Layer  // AnyExpr // '[Model, Type]
                    , Editor  // Net    // AnyExprLink
                    , Emitter // Delete // AnyExprLink
                    ]

watchRemoveNode :: Foo m => EventPassDef Delete (Expr l) m
watchRemoveNode = EventPassDef $ \t -> do
    inps   <- symbolFields (generalize t :: SomeExpr)
    tp     <- readLayer @Type t
    delete tp
    mapM_ delete inps

-- makePass 'watchRemoveNode


------------------
-- === Type === --
------------------

consTypeLayer :: (MonadRef m, Writers Net '[AnyExpr, Link' AnyExpr] m, Emitters '[New // Link' AnyExpr, New // AnyExpr] m)
              => Store.STRefM m (Maybe (Expr Star)) -> Expr t -> m (LayerData Type (Expr t))
consTypeLayer ref self = (`link` self) =<< unsafeRelayout <$> localTop ref ; {-# INLINE consTypeLayer #-}


localTop :: (MonadRef m, Writer Net AnyExpr m, Emitter (New // AnyExpr) m)
         => Store.STRefM m (Maybe (Expr Star)) -> m (Expr Star)
localTop ref = Store.readSTRef ref >>= \case
    Just t  -> return t
    Nothing -> do
        s <- reserveStar
        Store.writeSTRef ref $ Just s
        registerStar s
        Store.writeSTRef ref Nothing
        return s
{-# INLINE localTop #-}


data InitType
type instance Abstract InitType = InitType
type instance Inputs  Net   (ElemScope InitType t) = '[]
type instance Outputs Net   (ElemScope InitType t) = '[AnyExpr, Link' AnyExpr]
type instance Inputs  Layer (ElemScope InitType t) = '[]
type instance Outputs Layer (ElemScope InitType t) = '[AnyExpr // Type]
type instance Inputs  Attr  (ElemScope InitType t) = '[]
type instance Outputs Attr  (ElemScope InitType t) = '[]
type instance Inputs  Event (ElemScope InitType t) = '[]
type instance Outputs Event (ElemScope InitType t) = '[New // AnyExpr, New // Link' AnyExpr]
type instance Preserves     (ElemScope InitType t) = '[]
instance KnownElemPass InitType where
    elemPassDescription = genericDescriptionP

initType :: PrimMonad m => m (ExprLayerConsM InitType m)
initType = do
    ref <- Store.newSTRef (Nothing :: Maybe (Expr Star))
    return $ ExprLayerCons $ \(el, _) -> do
        t <- consTypeLayer ref el
        flip (writeLayer @Type) el t
{-# INLINE initType #-}



initType2 :: Req m '[ Writer  // Layer // AnyExpr // Type
                    , Writer  // Net   // '[AnyExpr, AnyExprLink]
                    , Emitter // New   // '[AnyExpr, AnyExprLink]
                    ]
          => STRefM m (Maybe (Expr Star)) -> ElemEventPassDef New (EXPR l) m
initType2 ref = eventPassDef $ \(el, _) -> flip (writeLayer @Type) el =<< consTypeLayer ref el
{-# INLINE initType2 #-}

initType2Pass :: STRef s (Maybe (Expr Star)) -> ElemEventPass2 New (EXPR l) InitType s
initType2Pass r = ElemEventPass2 $ initType2 r
--
-- init2 :: (MonadPassManager m, MonadPassManager (GetRefHandler m), Pass.DataLookup (GetRefHandler m)) => m ()
-- init2 = do
--     ref <- Store.newSTRef (def :: ID)
--     registerGenLayer (getTypeDesc @Type) (initType2Pass ref)
--




-------------------------------------------
-------------------------------------------
-------------------------------------------
-------------------------------------------


runRegs :: (MonadPassManager m, MonadPassManager (GetRefHandler m), Pass.DataLookup (GetRefHandler m)) => m ()
runRegs = do
    runElemRegs

    init1
    init2
    init3
    -- registerGenLayer  (getTypeDesc @Model) initModel
    -- registerGenLayerM (getTypeDesc @UID)   initUID
    -- registerGenLayer  (getTypeDesc @Succs) initSuccs

    registerExprLayerM2 (getTypeDesc @Type) initType

    attachLayer 0 (getTypeDesc @Model) (getTypeDesc @AnyExpr)
    attachLayer 0 (getTypeDesc @Model) (getTypeDesc @(Link' AnyExpr))
    attachLayer 5 (getTypeDesc @UID)   (getTypeDesc @AnyExpr)
    attachLayer 5 (getTypeDesc @UID)   (getTypeDesc @(Link' AnyExpr))
    attachLayer 5 (getTypeDesc @Succs) (getTypeDesc @AnyExpr)


    attachLayer 10 (getTypeDesc @Type) (getTypeDesc @AnyExpr)



    -- addEventListener 100 (Tag [getTypeDesc @Delete, getTypeDesc @(Link' AnyExpr)]) $ foo watchRemoveNode


-- === Elem reg defs === --

runElemRegs :: MonadIR m => m ()
runElemRegs = sequence_ [elemReg1, elemReg2, elemReg3]

elemReg1 :: MonadIR m => m ()
elemReg1 = registerElem @AnyExpr

elemReg2 :: MonadIR m => m ()
elemReg2 = registerElem @(Link' AnyExpr)

elemReg3 :: MonadIR m => m ()
elemReg3 = registerElem @(GROUP AnyExpr)


-- === Layer reg defs === --

layerRegs :: MonadIR m => [m ()]
layerRegs = [] -- [layerReg1, layerReg2, layerReg3, layerReg4]

runLayerRegs :: MonadIR m => m ()
runLayerRegs = sequence_ layerRegs





----------------------------------
----------------------------------
----------------------------------


source :: (MonadRef m, Reader Layer (Abstract (Link a b) // Model) m) => Link a b -> m a
source = fmap fst . readLayer @Model ; {-# INLINE source #-}

-- strName :: _ => _
strName v = getName v >>= \n -> match' n >>= \ (Term.Sym_String s) -> return s



-- === KnownExpr === --

type KnownExpr l m = (MonadRef m, Readers Layer '[AnyExpr // Model, Link' AnyExpr // Model] m) -- CheckAtomic (ExprHead l))

match' :: forall l m. KnownExpr l m => Expr l -> m (ExprHeadDef l)
match' = unsafeToExprTermDef @(ExprHead l)

modifyExprTerm :: forall l m. (KnownExpr l m, Writer Layer (AnyExpr // Model) m) => Expr l -> (ExprHeadDef l -> ExprHeadDef l) -> m ()
modifyExprTerm = unsafeModifyExprTermDef @(ExprHead l)

getSource :: KnownExpr l m => Lens' (ExprHeadDef l) (ExprLink a b) -> Expr l -> m (Expr a)
getSource f v = match' v >>= source . view f ; {-# INLINE getSource #-}


-- === KnownName === --

type       KnownName l m = (KnownExpr l m, HasName (ExprHeadDef l))
getName :: KnownName l m => Expr l -> m (Expr (Sub NAME l))
getName = getSource name ; {-# INLINE getName #-}







type family Head a

type instance Access AnyExpr (ENT e _ _) = e
type instance Access AnyExpr (E   e    ) = e
type instance Head (Atomic a) = Atomic a

type ExprHead l = Head (l # AnyExpr)
type ExprHeadDef l = ExprTermDef (ExprHead l) (Expr l)



---------- TRASH
------ TO BE DELETED WHEN POSSIBLE

instance MonadLogging m => MonadLogging (DepState.StateT a b m)
