//
//  PageFindScript.swift
//  PreviewViews
//
//  The script that finds and marks text in a sealed web page.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The script a host evaluates in a sealed page to find text in it: every match marked, one current.
public enum PageFindScript {
    /// The find script for `query`: it clears the last marks, marks every match in the page's text
    /// (`mark.sw-find`), makes the one at `index` current and scrolls to it, and evaluates to the
    /// count. It runs only DOM work and reaches no transport, so the offline seal holds
    /// (`allowsContentJavaScript = false` governs the PAGE's scripts, not `evaluateJavaScript`). Case is
    /// folded one UTF-16 unit at a time, never by a lowercasing that changes the text's length (`İ`
    /// lowercases to two units, which shifted every later mark). Matches inside one text node only: a query spanning a style
    /// boundary ("bold text" across `<strong>`) is not found, which the count reflects.
    public static func script(query: String, caseSensitive: Bool, index: Int?) -> String {
        """
        (function(q, cs, idx){
          var CLS = 'sw-find', CUR = 'sw-find-current';
          if (!document.body) return 0;
          var old = document.querySelectorAll('mark.' + CLS);
          for (var i = 0; i < old.length; i++) { var m = old[i], p = m.parentNode; while (m.firstChild) p.insertBefore(m.firstChild, m); p.removeChild(m); p.normalize(); }
          if (!q) return 0;
          if (!document.getElementById('sw-find-style')) {
            var st = document.createElement('style'); st.id = 'sw-find-style';
            st.textContent = 'mark.sw-find{background:rgba(255,213,0,.45);color:inherit;border-radius:2px}mark.sw-find.sw-find-current{background:rgba(255,140,0,.9);color:#000}';
            document.head.appendChild(st);
          }
          var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, { acceptNode: function(n) {
            var t = n.parentNode && n.parentNode.tagName;
            if (t === 'SCRIPT' || t === 'STYLE' || t === 'NOSCRIPT') return NodeFilter.FILTER_REJECT;
            return n.nodeValue.length ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT; } });
          var nodes = []; while (walker.nextNode()) nodes.push(walker.currentNode);
          function fold(s) { var o = ''; for (var i = 0; i < s.length; i++) { var c = s[i], l = c.toLowerCase(); o += l.length === 1 ? l : c; } return o; }
          var needle = cs ? q : fold(q), marks = [];
          for (var n = 0; n < nodes.length; n++) {
            var node = nodes[n], text = node.nodeValue, hay = cs ? text : fold(text), pos = hay.indexOf(needle);
            if (pos < 0) continue;
            var frag = document.createDocumentFragment(), last = 0;
            while (pos >= 0) {
              if (pos > last) frag.appendChild(document.createTextNode(text.slice(last, pos)));
              var mk = document.createElement('mark'); mk.className = CLS; mk.textContent = text.slice(pos, pos + needle.length);
              frag.appendChild(mk); marks.push(mk); last = pos + needle.length; pos = hay.indexOf(needle, last);
            }
            if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
            node.parentNode.replaceChild(frag, node);
          }
          if (marks.length && idx !== null) { var k = ((idx % marks.length) + marks.length) % marks.length; marks[k].classList.add(CUR); marks[k].scrollIntoView({ block: 'center', inline: 'nearest' }); }
          return marks.length;
        })(\(literal(query)), \(caseSensitive), \(index.map(String.init) ?? "null"))
        """
    }

    /// `s` as a JavaScript string literal: quotes, backslashes, line breaks and control characters escaped.
    public static func literal(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\u{2028}": out += "\\u2028"
            case "\u{2029}": out += "\\u2029"
            default: if u.value < 0x20 { out += String(format: "\\u%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        return out + "\""
    }
}
