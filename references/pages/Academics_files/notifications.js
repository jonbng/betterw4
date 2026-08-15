jQuery(function ($) {

    $('#header div.notifications').on('click', 'img.notification-icon', function (e) {
        e.stopPropagation();
        $('#header div.dropdown-menu').toggle();
    });
    $('#header div.notifications').on('click', 'h3.tasks a.read', function () {
        $.post(notification_urls.readAll, {}, function (data) {
            updateNotifications(data);
        });
        return false;
    });
    $('#header div.notifications').on('click', 'h3.emails a.read', function () {
        $.post(notification_urls.readAllEmails, {}, function (data) {
            updateNotifications(data);
        });
        return false;
    });
    $('#header div.notifications').on('click', 'dt a.read', function () {
        $.post(notification_urls.readGroup, {notification_type: $(this).attr('data-notification-type')}, function (data) {
            updateNotifications(data);
        });
        return false;
    });
    $('#header div.notifications').on('click', 'dd li a.read', function () {
        $.post(notification_urls.read, {notification_id: $(this).attr('data-notification-id')}, function (data) {
            updateNotifications(data);
        });
        return false;
    });

    $('#header div.notifications').on('click', 'h3 a.clear', function () {
        $.post(notification_urls.clearAll, {}, function (data) {
            updateNotifications(data);
        });
        return false;
    });
    $('#header div.notifications').on('click', 'dt a.clear', function () {
        $.post(notification_urls.clearGroup, {notification_type: $(this).attr('data-notification-type')}, function (data) {
            updateNotifications(data);
        });
        return false;
    });
    $('#header div.notifications').on('click', 'dd li a.clear', function () {
        $.post(notification_urls.clear, {notification_id: $(this).attr('data-notification-id')}, function (data) {
            updateNotifications(data);
        });
        return false;
    });

    setInterval(function() {
        if (!$('#header div.dropdown-menu').is(':visible')) {
            $.post(notification_urls.refresh, {}, function (data) {
                updateNotifications(data);
            });
        }
    }, 60000);

    function updateNotifications(data)
    {
        var visible = false;
        if ($('#header div.dropdown-menu').is(':visible')) {
            visible = true;
        }
        $('#header div.notifications').html($(data).children());
        if (visible) {
            $('#header div.dropdown-menu').show();
        }
    }
});