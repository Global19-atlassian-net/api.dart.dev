// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library member;

import 'dart:html';

import 'package:dartdoc_viewer/item.dart';
import 'package:dartdoc_viewer/search.dart';
import 'package:polymer/polymer.dart';
@MirrorsUsed()
import 'dart:mirrors';
import 'app.dart' as app show viewer;
import 'package:dartdoc_viewer/location.dart';

class SameProtocolUriPolicy implements UriPolicy {
  final AnchorElement _hiddenAnchor = new AnchorElement();
  final Location _loc = window.location;

  bool allowsUri(String uri) {
    _hiddenAnchor.href = uri;
    // IE leaves an empty protocol for same-origin URIs.
    var older = _hiddenAnchor.protocol;
    var newer = _loc.protocol;
    if ((older == "http:" && newer == "https:")
        || (older == "https:" && newer == "http:")) {
      return true;
    }
    return (older == newer || older == ':');
  }
}

var uriPolicy = new SameProtocolUriPolicy();
var validator = new NodeValidatorBuilder()
    ..allowElement("a", attributes: ["rel"])
    ..allowHtml5(uriPolicy: uriPolicy);

var sanitizer = new NullTreeSanitizer();

// TODO(alanknight): Switch to using the validator, verify it doesn't slow
// things down too much, and that it's not disallowing valid content.
/// A sanitizer that allows anything to maximize speed and not disallow any
/// tags.
class NullTreeSanitizer implements NodeTreeSanitizer {
  void sanitizeTree(Node node) {}
}

//// An abstract class for all Dartdoc elements.
// TODO(sigmund): remove 'with ChangeNotifier', that wont be needed after the
// next release of polymer
@reflectable abstract class DartdocElement extends PolymerElement
    with ChangeNotifier {
  DartdocElement.created() : super.created();

  get applyAuthorStyles => true;

  @observable get viewer => app.viewer;

  /// Find the old values of all of our [observables], run the function
  /// [thingToDo], then find new values and call [notifyPropertyChange] for
  /// each with the old and new values. Also notify all [methodsToCall].
  notifyObservables(Function thingToDo) {
    var oldValues = observableValues;
    thingToDo();
    var newValues = observableValues;
    observables.forEach((symbol) =>
      notifyPropertyChange(symbol, oldValues[symbol], newValues[symbol]));
    methodsToCall.forEach((symbol) =>
      notifyPropertyChange(symbol, null, 'changeNoMatterWhat'));
  }

  List<Symbol> get observables => const [];
  List<Symbol> get methodsToCall => const [#addComment];
  Iterable concat(Iterable list1, Iterable list2)
      => [list1, list2].expand((x) => x);

  get observableValues => new Map.fromIterables(
      observables,
      observables.map((symbol) => mirror.getField(symbol).reflectee));

  InstanceMirror _cachedMirror;
  get mirror =>
      _cachedMirror == null ? _cachedMirror = reflect(this) : _cachedMirror;

  enteredView() {
    super.enteredView();
    // Handle clicks and redirect.
    onClick.listen(handleClick);
  }

  var _pathname = window.location.pathname;

  void handleClick(Event e) {
    if (e.target is AnchorElement) {
      var anchor = e.target;
      if (anchor.host == window.location.host
          && anchor.pathname == _pathname && !(e as MouseEvent).ctrlKey) {
        e.preventDefault();
        var location = anchor.hash.substring(1, anchor.hash.length);
        viewer.handleLink(location);
      }
    }
  }
}

//// This is a web component to be extended by all Dart members with comments.
//// Each member has an [Item] associated with it as well as a comment to
//// display, so this class handles those two aspects shared by all members.
@reflectable abstract class MemberElement extends DartdocElement {
  MemberElement.created() : super.created() {
    _item = defaultItem;
  }

  bool wrongClass(newItem);
  get defaultItem;
  var _item;

  Iterable<Symbol> get observables =>
      concat(super.observables, const [#item, #idName]);

  @published set item(newItem) {
    if (newItem == null || wrongClass(newItem)) return;
    notifyObservables(() => _item = newItem);
  }
  @published get item => _item == null ? _item = defaultItem : _item;

  /// A valid string for an HTML id made from this [Item]'s name.
  @observable String get idName {
    if (item == null) return '';
    var loc = item.anchorHrefLocation;
    return loc.anchor == null ? '' : loc.anchor;
  }

  /// Adds [item]'s comment to the the [elementName] element with markdown
  /// links converted to working links.
  void addComment(String elementName, [bool preview = false,
      Element commentLocation]) {
    if (item == null) return;
    var comment = item.comment;
    if (commentLocation == null) {
      commentLocation = shadowRoot.querySelector('.description');
    }
    if (preview && (item is Class || item is Library))
      comment = item.previewComment;
    if (comment != '' && comment != null) {
      if (commentLocation == null) {
        commentLocation = shadowRoot.querySelector('.description');
      }
      if (commentLocation == null) return;
      commentLocation.children.clear();
      var commentElement = new Element.html(comment,
          validator: validator);
      var firstParagraph = (commentElement is ParagraphElement) ?
          commentElement : commentElement.querySelector("p");
      if (firstParagraph != null) {
        firstParagraph.classes.add("firstParagraph");
      }
      var links = commentElement.querySelectorAll('a');
      for (AnchorElement link in links) {
        _resolveLink(link);
      }
      commentLocation.children.add(commentElement);
    }
  }

  String _parameterName(AnchorElement link, DocsLocation loc) {
    var item = loc.items(viewer.homePage).last;
    var itemName = item.location.withoutAnchor;
    if (item is Method && itemName.length < link.text.length) {
      return link.text.substring(itemName.length + 1, link.text.length);
    } else {
      return null;
    }
  }

  void _replaceWithParameterReference(AnchorElement link, DocsLocation loc,
      String parameterName) {
    loc.anchor = loc.toHash("${loc.subMemberName}_$parameterName");
    loc.subMemberName = null;
    link.replaceWith(new Element.html(
        '<a href="#${loc.withAnchor}">$parameterName</a>',
        validator: validator));
  }

  void _resolveLink(AnchorElement link) {
    if (link.href != '') return;
    var loc = new DocsLocation(link.text);
    var parameterName = _parameterName(link, loc);
    if (parameterName != null) {
      _replaceWithParameterReference(link, loc, parameterName);
      return;
    }
    if (index.containsKey(link.text)) {
      _setLinkReference(link, loc);
      return;
    }
    loc.packageName = null;
    if (index.containsKey(loc.withAnchor)) {
      _setLinkReference(link, loc);
      return;
    }
    // If markdown links to private or otherwise unknown members are
    // found, make them <i> tags instead of <a> tags for CSS.
    link.replaceWith(new Element.html('<i>${link.text}</i>',
        validator: validator));
  }

  void _setLinkReference(AnchorElement link, DocsLocation loc) {
    var linkable = new LinkableType(loc.withAnchor);
    link
      ..href = '#${linkable.location}'
      ..text = linkable.simpleType;
  }

  /// Creates an HTML element for a parameterized type.
  static Element createInner(NestedType type) {
    var span = new SpanElement();
    if (index.containsKey(type.outer.qualifiedName)) {
      var outer = new AnchorElement()
        ..text = type.outer.simpleType
        ..href = '#${type.outer.location}';
      span.append(outer);
    } else {
      span.appendText(type.outer.simpleType);
    }
    if (type.inner.isNotEmpty) {
      span.appendText('<');
      type.inner.forEach((element) {
        span.append(createInner(element));
        if (element != type.inner.last) span.appendText(', ');
      });
      span.appendText('>');
    }
    return span;
  }

  /// Creates a new HTML element describing a possibly parameterized type
  /// and adds it to [memberName]'s tag with class [className].
  void createType(NestedType type, String memberName, String className) {
    if (type == null) return;
    var location = shadowRoot.querySelector('.$className');
    if (location == null) return;
    location.children.clear();
    if (!type.isDynamic) {
      location.children.add(createInner(type));
    }
  }
}

//// A [MemberElement] that could be inherited from another [MemberElement].
@reflectable abstract class InheritedElement extends MemberElement with ChangeNotifier  {
  InheritedElement.created() : super.created();

  @reflectable @observable LinkableType get inheritedFrom => __$inheritedFrom; LinkableType __$inheritedFrom; @reflectable set inheritedFrom(LinkableType value) { __$inheritedFrom = notifyPropertyChange(#inheritedFrom, __$inheritedFrom, value); }
  @reflectable @observable LinkableType get commentFrom => __$commentFrom; LinkableType __$commentFrom; @reflectable set commentFrom(LinkableType value) { __$commentFrom = notifyPropertyChange(#commentFrom, __$commentFrom, value); }

  get observables => concat(super.observables,
      const [#inheritedFrom, #commentFrom, #isInherited,
             #hasInheritedComment]);

  enteredView() {
    super.enteredView();
    if (isInherited) {
      inheritedFrom = new LinkableType(
          new DocsLocation(item.inheritedFrom).asHash.withAnchor);
    }
    if (hasInheritedComment) {
      commentFrom = new LinkableType(
          new DocsLocation(item.commentFrom).asHash.withAnchor);
    }
  }

  @observable bool get isInherited =>
      item != null && item.inheritedFrom != '' && item.inheritedFrom != null;

  @observable bool get hasInheritedComment =>
      item != null && item.commentFrom != '' && item.commentFrom != null;

  /// Returns whether [location] exists within the search index.
  @observable bool exists(String location) {
    if (location == null) return false;
    return index.containsKey(location);
  }
}

@reflectable class MethodElement extends InheritedElement {

  bool wrongClass(newItem) => newItem is! Method;

  MethodElement.created() : super.created();

  get defaultItem => new Method({
      "name" : "Loading",
      "qualifiedName" : "Loading",
      "comment" : "",
      "parameters" : null,
      "return" : [null],
    }, isConstructor: true);

  // TODO(alanknight): Remove this and other workarounds for bindings firing
  // even when their surrounding test isn't true. This ignores values of the
  // wrong type. IOssue 13386 and/or 13445
  // TODO(alanknight): Remove duplicated subclass methods. Issue 13937

  @observable List<Parameter> get parameters => item.parameters;
}
