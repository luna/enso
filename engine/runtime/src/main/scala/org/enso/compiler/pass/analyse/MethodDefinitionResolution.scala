package org.enso.compiler.pass.analyse

import org.enso.compiler.context.{InlineContext, ModuleContext}
import org.enso.compiler.core.IR
import org.enso.compiler.pass.IRPass
import org.enso.compiler.core.ir.MetadataStorage._
import org.enso.compiler.data.BindingsMap
import org.enso.compiler.exception.CompilerError

case object MethodDefinitionResolution extends IRPass {

  /** The type of the metadata object that the pass writes to the IR. */
  override type Metadata = BindingsMap.Resolution

  /** The type of configuration for the pass. */
  override type Config = IRPass.Configuration.Default

  /** The passes that this pass depends _directly_ on to run. */
  override val precursorPasses: Seq[IRPass] = List()

  /** The passes that are invalidated by running this pass. */
  override val invalidatedPasses: Seq[IRPass] = List()

  /** Executes the pass on the provided `ir`, and returns a possibly transformed
    * or annotated version of `ir`.
    *
    * @param ir            the Enso IR to process
    * @param moduleContext a context object that contains the information needed
    *                      to process a module
    * @return `ir`, possibly having made transformations or annotations to that
    *         IR.
    */
  override def runModule(
    ir: IR.Module,
    moduleContext: ModuleContext
  ): IR.Module = {
    val availableSymbolsMap = ir.unsafeGetMetadata(
      BindingResolution,
      "MethodDefinitionResolution is being run before BindingResolution"
    )
    val newDefs = ir.bindings.map {
      case method: IR.Module.Scope.Definition.Method.Explicit =>
        val methodRef = method.methodReference
        val resolvedTypeRef = methodRef.typePointer match {
          case tp: IR.Name.Here =>
            tp.updateMetadata(
              this -->> BindingsMap.Resolution(
                BindingsMap.ResolvedModule(availableSymbolsMap.currentModule)
              )
            )
          case tp @ IR.Name.Qualified(List(item), _, _, _) =>
            availableSymbolsMap.resolveUppercaseName(item.name) match {
              case Left(err) =>
                IR.Error.Resolution(tp, IR.Error.Resolution.Reason(err))
              case Right(candidate) =>
                tp.updateMetadata(this -->> BindingsMap.Resolution(candidate))
            }
          case tp: IR.Error.Resolution => tp
          case _ =>
            throw new CompilerError(
              "Unexpected kind of name for method reference"
            )

        }
        val resolvedMethodRef = methodRef.copy(typePointer = resolvedTypeRef)
        val resolvedMethod    = method.copy(methodReference = resolvedMethodRef)
        resolvedMethod
      case other => other
    }

    ir.copy(bindings = newDefs)
  }

  /** Executes the pass on the provided `ir`, and returns a possibly transformed
    * or annotated version of `ir` in an inline context.
    *
    * @param ir            the Enso IR to process
    * @param inlineContext a context object that contains the information needed
    *                      for inline evaluation
    * @return `ir`, possibly having made transformations or annotations to that
    *         IR.
    */
  override def runExpression(
    ir: IR.Expression,
    inlineContext: InlineContext
  ): IR.Expression = ir

}
