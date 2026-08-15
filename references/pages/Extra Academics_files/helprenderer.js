$(function () {
	$('#help_display').draggable({handle: '#help_title_bar'});
	$('.help').click(function() {
		var $this = $(this);
		var match = $this.attr('id').match(/^help-(.+)$/);
		var help_context = match ? match[1] : '';
		$('#help_content').html('');
		$('#help_display').show().center(true);
		//$('#loading').show();
		getHelp(help_context);
	});
	$('#help_index_link').click(function () {
		getHelp('');
	});
	$('#help_close_button').click(function () {
		$('#help_display').hide();
	});
});

function getHelp(help_context) {
	$('#help_content').get(0).src = ajax_help_url + '&help_context=' + help_context;
	//$.post(ajax_help_url, {help_context: help_context}, function (data) {
	//		$('#help_content').contents().html(data);
	//})
}