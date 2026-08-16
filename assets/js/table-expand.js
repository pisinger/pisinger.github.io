/**
 * Table expand — adds a zoom button to every markdown table in post/page
 * content and shows a full-viewport, scrollable copy in a modal dialog.
 *
 * Chirpy's `refactor-content.html` wraps every markdown table in
 * `<div class="table-wrapper">` and explicitly un-wraps Rouge's line-number
 * tables, so targeting `.table-wrapper > table` skips code blocks for free.
 *
 * No dependencies; inherits Chirpy's own table styling and light/dark vars.
 */
(function () {
  'use strict';

  var CONTENT_TABLE = '.content .table-wrapper > table';
  var modal = null;

  function buildModal() {
    var dialog = document.createElement('dialog');
    dialog.id = 'table-zoom-modal';
    dialog.innerHTML =
      '<div class="table-zoom-head">' +
      '<span class="table-zoom-hint">Press <kbd>Esc</kbd> to close</span>' +
      '<button type="button" class="table-zoom-close" aria-label="Close table view">' +
      '<i class="fas fa-times"></i>' +
      '</button>' +
      '</div>' +
      // `table-wrapper` so Chirpy's own table styles apply to the clone
      '<div class="table-zoom-body table-wrapper"></div>';

    dialog.querySelector('.table-zoom-close').addEventListener('click', function () {
      dialog.close();
    });

    // click on the backdrop area closes
    dialog.addEventListener('click', function (event) {
      if (event.target === dialog) {
        dialog.close();
      }
    });

    dialog.addEventListener('close', function () {
      dialog.querySelector('.table-zoom-body').replaceChildren();
      document.documentElement.classList.remove('table-zoom-open');
    });

    document.body.appendChild(dialog);
    return dialog;
  }

  function openModal(table) {
    if (modal === null) {
      modal = buildModal();
    }

    modal.querySelector('.table-zoom-body').replaceChildren(table.cloneNode(true));
    document.documentElement.classList.add('table-zoom-open');
    modal.showModal();
  }

  function decorate(table) {
    // The wrapper scrolls on overflow, so the button needs an outer,
    // non-scrolling box to stay pinned while the table scrolls underneath.
    var wrapper = table.parentElement;

    if (wrapper.parentElement.classList.contains('table-expand-box')) {
      return;
    }

    var box = document.createElement('div');
    box.className = 'table-expand-box';
    wrapper.parentElement.insertBefore(box, wrapper);
    box.appendChild(wrapper);

    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'table-expand-btn';
    btn.title = 'Expand table';
    btn.setAttribute('aria-label', 'Expand table');
    btn.innerHTML = '<i class="fas fa-expand"></i>';
    btn.addEventListener('click', function () {
      openModal(table);
    });

    box.appendChild(btn);
  }

  function init() {
    if (typeof HTMLDialogElement === 'undefined') {
      return; // no dialog support, leave tables untouched
    }

    document.querySelectorAll(CONTENT_TABLE).forEach(decorate);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
