onPage('registrations#edit_registrations', function() {
  var $registrationsTable = $('table.registrations-table:not(.floatThead-table)');

  var showHideActions = function(e) {
    var $selectedRows = $registrationsTable.find("tr.selected");
    $('.selected-registrations-actions').toggle($selectedRows.length > 0);

    var $selectedApprovedRows = $selectedRows.filter(".registration-accepted");
    $('.selected-approved-registrations-actions').toggle($selectedApprovedRows.length > 0);

    var $selectedPendingRows = $selectedRows.filter(".registration-pending");
    $('.selected-pending-registrations-actions').toggle($selectedPendingRows.length > 0);

    var emails = $selectedRows.find("a[href^=mailto]").map(function() { return this.href.match(/^mailto:(.*)/)[1]; }).toArray();
    document.getElementById("email-selected").href = "mailto:?bcc=" + emails.join(",");
  };
  $registrationsTable.on('check.bs.table uncheck.bs.table check-all.bs.table uncheck-all.bs.table', function() {
    // Wait in order to let bootstrap-table script add a 'selected' class to the appropriate rows
    setTimeout(showHideActions, 0);
  });
  showHideActions();

  $('button[value=delete-selected]').on("click", function(e) {
    var $selectedRows = $registrationsTable.find("tr.selected");
    if(!confirm("Delete the " + $selectedRows.length + " selected registrations?")) {
      e.preventDefault();
    }
  });
});

onPage('registrations#index', function() {
  // To improve performance we do the first sorting by name server-side.
  // This makes the interface resemble the order.
  $('.name .sortable').addClass('asc');
});
