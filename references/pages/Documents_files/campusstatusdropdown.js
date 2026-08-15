jQuery(function ($) {
    $('.status-dropdown').on('click', function () {
        $('.selection-box').css({top: $('.status-dropdown').position().top + $('.status-dropdown').height() + 15, right: 0});
        $('.selection-box').toggle();
    });
    $('#submit-campus-status').on('click', function () {
        var selection = $('input[name=location]:checked').length === 1 ? $('input[name=location]:checked').val() : null;
        if (!selection) {
            alert('Choose your current location');
            return;
        }
        if (selection === 'other' && !$('#other').val()) {
            alert('Enter your current location');
            return;
        }

        var status = selection === 'oncampus' ? 'on' : 'off';
        var location = selection === 'oncampus' ? null : (selection === 'other' ? $('#other').val() : selection);
        $.post(status_urls.set, {status: status, location: location}, function () {
            $('.selection-box').hide();
            if (status === 'on') {
                $('.status-dropdown .status').removeClass('offcampus').addClass('oncampus');
                $('.status-dropdown .status-value').text('on campus');
                $('.status-dropdown .location').text('');
            } else {
                $('.status-dropdown .status').removeClass('oncampus').addClass('offcampus');
                $('.status-dropdown .status-value').text('off campus');
                $('.status-dropdown .location').text('(' + location + ')');
            }
        });
    });
    $('input[name=location]').on('click', function () {
        if ($(this).val() === 'other') {
            $('#other').show();
        } else {
            $('#other').hide();
        }
    });
    if ($('input[name=location]:checked').length === 1 && $('input[name=location]:checked').val() === 'other') {
        $('#other').show();
    } else {
        $('#other').hide();
    }
});