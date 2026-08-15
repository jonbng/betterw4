jQuery(function ($) {
    $('#preib-year-switch').click(function () {
        var classToSwitch;
        if (!$('#preib-year-switch').hasClass('year-switch-active')) {
            if ($('#first-year-switch').hasClass('year-switch-active')) {
                classToSwitch = 'first-year';
            } else {
                classToSwitch = 'second-year';
            }
            $('.year-switch-active').removeClass('year-switch-active');
            $('#preib-year-switch').addClass('year-switch-active');
            $('.' + classToSwitch).fadeOut(300, function () {
                $('.preib-year').fadeIn(300);
            });
        }
    });

    $('#first-year-switch').click(function () {
        var classToSwitch;
        if (!$('#first-year-switch').hasClass('year-switch-active')) {
            if ($('#preib-year-switch').hasClass('year-switch-active')) {
                classToSwitch = 'preib-year';
            } else {
                classToSwitch = 'second-year';
            }
            $('.year-switch-active').removeClass('year-switch-active');
            $('#first-year-switch').addClass('year-switch-active');
            $('.' + classToSwitch).fadeOut(300, function () {
                $('.first-year').fadeIn(300);
            });
        }
    });

    $('#second-year-switch').click(function () {
        var classToSwitch;
        if (!$('#second-year-switch').hasClass('year-switch-active')) {
            if ($('#preib-year-switch').hasClass('year-switch-active')) {
                classToSwitch = 'preib-year';
            } else {
                classToSwitch = 'first-year';
            }
            $('.year-switch-active').removeClass('year-switch-active');
            $('#second-year-switch').addClass('year-switch-active');
            $('.' + classToSwitch).fadeOut(300, function () {
                $('.second-year').fadeIn(300);
            });
        }
    });

});