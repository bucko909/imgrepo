//window.addEventListener('load', initialise, false);
initialise();

var tagform;
var tagbox;
var tagdisp;
var ratingdisp;
var stat_msg;
var autocomplete;

var xhttp_t;
var xhttp_r;

function initialise() {
	tagform = document.getElementById("tagform");
	tagbox = document.getElementById("tagbox");
	tagdisp = document.getElementById("tags");
	ratingdisp = document.getElementById("rating");
	stat_msg = document.getElementById("statmsg");
	image_id = document.getElementById("imageid");
	autocomplete = document.getElementById("autocomplete");
	xhttp_t = new XMLHttpRequest();
	xhttp_r = new XMLHttpRequest();
	document.getElementById("editlinklink").addEventListener('click', show_editor, false);
	tagform.addEventListener('submit', submit_tags, false);
	tagbox.addEventListener('keydown', tagbox_autocomplete, false);
	tagbox.addEventListener('keypress', tagbox_keypress, false);
	get_tags();
	get_rating();
}

function test_xhttp_t() {
	if (!xhttp_t)
		return 0;
	if (xhttp_t.readyState == 0 || xhttp_t.readyState == 4)
		return 1;
	return 0;
}

function test_xhttp_r() {
	if (!xhttp_r)
		return 0;
	if (xhttp_r.readyState == 0 || xhttp_r.readyState == 4)
		return 1;
	return 0;
}

function show_editor(e) {
	e.preventDefault();
	document.getElementById('editlink').style.display = 'none';
	document.getElementById('editor').style.display = 'block';
}

function get_tags() {
	if (!test_xhttp_t())
		return; // Busy
	xhttp_t.open("GET","tag_list?img=" + image_id.value,true);
	xhttp_t.onreadystatechange = tags_got;
	xhttp_t.send('');
}

var image_tag_id_list = new Array();
function tags_got() {
	if (xhttp_t.readyState != 4)
		return;
	
	var tag_output = xhttp_t.responseText.split(/\n/);
	var i;
	image_tag_list = new Array();
	clear_box(tagdisp);
	for(i=0; i<tag_output.length; i++) {
		if (!tag_output[i])
			continue;
		var bits = tag_output[i].split(/ /);
		if (i)
			tagdisp.appendChild(document.createTextNode(" "));
		var link = document.createElement("a");
		link.href="index?tag="+bits[1]+"%3A"+bits[2];
		link.appendChild(document.createTextNode(parseInt(bits[3]) ? bits[1] + " (" + bits[2] + ")" : bits[1]));
		image_tag_id_list.push(bits[0]);
		tagdisp.appendChild(link);
	}
}

function get_rating() {
	if (!test_xhttp_r())
		return; // Busy
	xhttp_r.open("GET","rating_status?img=" + image_id.value,true);
	xhttp_r.onreadystatechange = rating_got;
	xhttp_r.send('');
}

function rating_got() {
	if (xhttp_r.readyState != 4)
		return;
	
	clear_box(ratingdisp);
	var vote_output = xhttp_r.responseText.split("\n");
	if (vote_output[0] == "nosess") {
		ratingdisp.appendChild(document.createTextNode("Rating: " + vote_output[1] + " (no session)."));
	} else if (vote_output[0] == "rated") {
		ratingdisp.appendChild(document.createTextNode("Rating: " + vote_output[1] + " (already rated)."));
	} else if (vote_output[0] == "rateable") {
		ratingdisp.appendChild(document.createTextNode("Rating: " + vote_output[1] + " ("));
		var link1 = document.createElement("a");
		link1.href="#";
		link1.addEventListener('click', rating_rate, false);
		link1.votedirection="up";
		link1.appendChild(document.createTextNode("+"));
		ratingdisp.appendChild(link1);
		ratingdisp.appendChild(document.createTextNode("/"));
		var link2 = document.createElement("a");
		link2.href="#";
		link2.addEventListener('click', rating_rate, false);
		link2.votedirection="down";
		link2.appendChild(document.createTextNode("-"));
		ratingdisp.appendChild(link2);
		ratingdisp.appendChild(document.createTextNode(")."));
	} else {
		ratingdisp.appendChild(document.createTextNode("Rating: Error."));
	}
}

function rating_rate(e) {
	e.preventDefault();
	if (!test_xhttp_r())
		return; // Busy
	
	clear_box(ratingdisp);
	ratingdisp.appendChild(document.createTextNode("Please wait..."));

	xhttp_r.open("GET","rating_submit?img=" + image_id.value + "&rating=" + e.currentTarget.votedirection, true);
	xhttp_r.onreadystatechange = rating_done;
	xhttp_r.send('');
}

function rating_done() {
	if (xhttp_r.readyState != 4)
		return;
	
	clear_box(ratingdisp);
	var vote_output = xhttp_r.responseText;
	if (vote_output == "error") {
		ratingdisp.appendChild(document.createTextNode("Rating error 1"));
	} else if (vote_output == "nosess") {
		ratingdisp.appendChild(document.createTextNode("Rating failed (no session)."));
	} else if (vote_output == "already_rated") {
		ratingdisp.appendChild(document.createTextNode("Rating failed (already rated)."));
	} else if (vote_output == "rated") {
		ratingdisp.appendChild(document.createTextNode("Rating changed; please wait..."));
		get_rating();
	}
}

function submit_tags(e) {
	if (autocomplete_timer)
		clearTimeout(autocomplete_timer);
	autocomplete.style.display = 'none';
	stat_msg.style.display = 'none';
	if (!test_xhttp_t())
		return; // Busy
	e.preventDefault();
	var tags = tagbox.value.split(/ +/);
	var submit_str = "img="+image_id.value;
	var i;
	for(i = 0; i < tags.length; i++) {
		var str = tags[i];
		str = str.replace(/:/, "%3A");
		str = str.replace("'", "%27");
		if (!str)
			continue;
		submit_str += "&";
		submit_str += "tag=" + str;
	}
	xhttp_t.open("GET","tag_submit?" + submit_str,true);
	xhttp_t.onreadystatechange = submit_done;
	xhttp_t.send('');
}

function submit_done() {
	if (xhttp_t.readyState != 4)
		return;
	
	var tag_output = xhttp_t.responseText.split(/\n/);
	if (tag_output[0]) {
		// Something worked; update tags list.
	}
	clear_box(stat_msg);
	stat_msg.style.left = tagbox.style.left;
	stat_msg.style.top = tagbox.style.bottom;
//	if (tag_output[1]) {
		// Something failed; show status and rebuild editor.
		var i;
		var j, k;
		tagbox.value = '';
		for(i=0; i < tag_output.length; i++) {
			if (!tag_output[i])
				continue;
			if (j)
				stat_msg.appendChild(document.createElement("br"));
			stat_msg.appendChild(document.createTextNode(tag_output[i]));
			j=1;
			if (i==0)
				continue;
			var bits = tag_output[i].split(/: /);
			if (k)
				tagbox.value += ' ';
			tagbox.value += bits[1];
			k=1;
		}
//	}
	stat_msg.style.display = 'block';
	get_tags();
}

var autocomplete_timer;
function tagbox_autocomplete(e) {
	if (autocomplete_timer)
		clearTimeout(autocomplete_timer);
	
	if (e.keyCode == 38 || e.keyCode == 40) {
		e.preventDefault();
		return;
	}

	// Prevent tab getting nommed by Opera.
	if (e.keyCode == 9) {
		e.preventDefault();
		var f;
		f = function (e) {
			tagbox.focus();
		};
		document.getElementById("tagsubmitbutton").addEventListener("focus",f,false);
	}

	autocomplete.style.display = 'none';
	stat_msg.style.display = 'none';
	if (!test_xhttp_t())
		return;
	
	if (!tagbox.value.match(/^[a-z0-9_': @./!?\\-]*$/)) {
		return;
	}

	autocomplete_timer = setTimeout("tagbox_autocomplete_1()", 400);
}

var ac_before;
var ac_after;
function tagbox_autocomplete_1() {
	var regex = /[a-z0-9'_@./!?-]+\\[a-z0-9'_@./!?:-]*|[a-z0-9'_@./!?-]*\\[a-z0-9'_@./!?:-]+/;
	var str = regex.exec(tagbox.value);
	if (str) {
		str = new String(str);
		var offset = tagbox.value.indexOf(str);
		ac_before = tagbox.value.substring(0, offset);
		ac_after = tagbox.value.substring(offset + str.length, tagbox.value.length);
		if (ac_after.indexOf('\\') >= 0) {
			return;
		}
	} else if (tagbox.value.match(/^$| $/)) {
		var tag_query = '';
		var i;
		for(i = 0; i < image_tag_id_list.length; i++) {
			tag_query += "&tag_id=" + image_tag_id_list[i];
		}
		var tag_split = tagbox.value.split(/ /);
		for(i = 0; i < tag_split.length; i++) {
			if (!tag_split[i] || tag_split[i].match(/[^a-z0-9_': @./!?\\-]/))
				continue;
			tag_query += "&tag=" + tag_split[i];
		}
		ac_before = tagbox.value;
		ac_after = "";
		xhttp_t.open('GET','tag_suggest?'+tag_query,true);
		xhttp_t.onreadystatechange = tagbox_autocomplete_2;
		xhttp_t.send('');
		return;
	} else {
		var offset = tagbox.value.lastIndexOf(' ') + 1;
		ac_before = tagbox.value.substring(0, offset);
		ac_after = "";
		str = tagbox.value.substring(offset, tagbox.value.length);
	}
	str = str.replace(/(?:\\)/g, "");
	str = str.replace("'", "%27");
	str = str.replace(/:.*/, "");

	if (!str) {
		return;
	}

	xhttp_t.open('GET','tag_autocomplete?partial='+str,true);
	xhttp_t.onreadystatechange = tagbox_autocomplete_2;
	xhttp_t.send('');
}

var ac_options;
var ac_selected;
function tagbox_autocomplete_2() {
	if (xhttp_t.readyState != 4)
		return;
	
	var got_options = xhttp_t.responseText;
	if (!got_options)
		return;
	ac_options = got_options.split(/\n/);
	ac_selected = -1;
	// The top option should be actually in the text.
	clear_box(autocomplete);

	// Add all options to the dropdown.
	autocomplete.style.left = tagbox.style.left;
	autocomplete.style.top = tagbox.style.bottom;
	var i;
	for(i=0; i<ac_options.length; i++) {
		var bits = ac_options[i].split(/ /);
		var completion = document.createElement('span');
		bits[5] = completion;
		ac_options[i] = bits;
		completion.appendChild(document.createTextNode(bits[1] + " (" + bits[2] + ")"));
		completion.addEventListener('click', tagbox_select_autocomplete, false);
		completion.tag_id = bits[0];
		completion.tag_name = bits[1] + ":" + bits[2];
		completion.offset_id = i;
		if (i)
			autocomplete.appendChild(document.createElement('br'));
		autocomplete.appendChild(completion);
	}
	autocomplete.style.display = 'block';
}

function tagbox_select_autocomplete(e) {
	autocomplete.style.display = 'none';
	autocomplete_selected(e.currentTarget);
}

function autocomplete_selected(o) {
	tagbox.value = ac_before + o.tag_name + ac_after;
}

function tagbox_keypress(e) {
	if (e.keyCode != 38 && e.keyCode != 40)
		return;
	
	if (!ac_options) {
		return;
	}

	if (ac_selected >= 0) {
		ac_options[ac_selected][5].style.background = '#F66';
	}
	// down = 40
	// up = 38

	if (e.keyCode == 38) {
		if (ac_selected <= 0)
			ac_selected = ac_options.length - 1;
		else
			ac_selected--;
	} else {
		if (ac_selected >= ac_options.length - 1)
			ac_selected = 0;
		else
			ac_selected++;
	}
	if (ac_selected >= 0) {
		ac_options[ac_selected][5].style.background = '#FF6';
	}
	autocomplete_selected(ac_options[ac_selected][5]);
	e.preventDefault();
}

function clear_box(box) {
	while(box.firstChild) {
		box.removeChild(box.firstChild);
	}
}
