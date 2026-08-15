jQuery(function ($) {
	blink();

	function blink() {
		$("#current_time").fadeTo(500, 0).fadeTo(500, 0.5, function(){
			var pixel = timeToPixel();
			if (pixel > 0) {
				$(this).css('top', pixel);blink()
			} else {
				$('#current_time').hide();
			}
		});
	}

	function timeToPixel() {
		var date1 = new Date();
		var date2 = new Date();
		date2.setHours(tt_start_hour, 0, 0, 0);
		if (date1.getHours() >= tt_start_hour && date1.getHours() < tt_end_hour) {
			return Math.round((date1.getTime() - date2.getTime()) / 60000);
		} else {
			return -1;
		}
	}
})