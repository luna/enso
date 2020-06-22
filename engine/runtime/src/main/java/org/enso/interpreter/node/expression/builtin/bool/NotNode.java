package org.enso.interpreter.node.expression.builtin.bool;

import com.oracle.truffle.api.nodes.Node;
import org.enso.interpreter.dsl.BuiltinMethod;

@BuiltinMethod(type = "Boolean", name="not")
public class NotNode extends Node {
  public boolean execute(boolean self) {
    return !self;
  }
}