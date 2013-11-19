// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library parameters;

import 'dart:html';

import 'package:dartdoc_viewer/item.dart';
import 'package:polymer/polymer.dart';

import 'app.dart';
import 'member.dart';

@CustomTag("dartdoc-parameter")
class ParameterElement extends DartdocElement {
  ParameterElement.created() : super.created();

  get observables => concat(super.observables, const [#required, #optional,
      #optionalOpeningDelimiter, #optionalClosingDelimiter]);
  get methodsToCall => concat(super.methodsToCall, const [#addAllParameters]);

  List<Parameter> _parameters = const [];
  @published get parameters => _parameters;
  @published set parameters(newParameters) {
    notifyObservables(() => _parameters = newParameters);
  }

  // Required parameters.
  @observable List<Parameter> get required =>
    parameters.where((parameter) => !parameter.isOptional).toList();

  // Optional parameters.
  @observable List<Parameter> get optional =>
    parameters.where((parameter) => parameter.isOptional).toList();

  @observable get optionalOpeningDelimiter =>
      optional.isEmpty ? '' : optional.first.isNamed ? '{' : '[';

  @observable get optionalClosingDelimiter =>
      optional.isEmpty ? '' : optional.first.isNamed ? '}' : ']';

  addAllParameters() {
    var location = shadowRoot.querySelector('.required');
    if (location == null) return;
    location.children.clear();
    location.appendText('(');
    addParameters(required, 'required', location);
    addParameters(optional, 'optional', location);
    location.appendText(')');
  }

  /// Adds [elements] to the tag with class [className].
  void addParameters(List<Parameter> elements, String className, var location) {
    if (elements.isEmpty) return;
    if (location == null) return;
    var outerSpan = new SpanElement();
    if (className == 'optional') {
      outerSpan.appendText(optionalOpeningDelimiter);
    }
    elements.forEach((element) {
      // Since a dartdoc-annotation cannot be instantiated from Dart code,
      // the annotations must be built manually.
      element.annotations.annotations.forEach((annotation) {
        var anchor = new AnchorElement()
          ..text = '@${annotation.simpleType}'
          ..href = '#${annotation.location}';
        outerSpan.append(anchor);
        outerSpan.appendText(' ');
      });
      // Skip dynamic as an outer parameter type (but not as generic)
      var space = '';
      if (!element.type.isDynamic) {
        outerSpan.append(MemberElement.createInner(element.type));
        space = ' ';
      }
      var parameterName = new AnchorElement()
        ..text = element.name
        ..href = "#${element.anchorHref}"
        ..id = "${element.anchorHrefLocation.anchor}";
      outerSpan.appendText(space);
      outerSpan.append(parameterName);
      outerSpan.appendText(element.decoration);
      if (className == 'required' && optional.isNotEmpty ||
          element != elements.last) {
        outerSpan.appendText(', ');
      }
    });
    if (className == 'optional') {
      outerSpan.appendText(optionalClosingDelimiter);
    }
    location.children.add(outerSpan);
  }
}