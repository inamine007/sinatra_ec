let num = 1;
function appendForm() {
  dom = `
    <div id="var_form_${num}">
      <hr>
      <div>
        <label for="var_content_${num}">内容: </label>
        <input type="text" name="var_content_${num}" id="var_content_${num}" required>
      </div>
      <div>
        <label for="var_price_${num}">値段: </label>
        <input type="number" name="var_price_${num}" id="var_price_${num}" required>
      </div>
      <button onClick="removeForm(${num})">削除</button>
    </div>
  `
  $('#var_group').append(dom);
  num++;
}

function removeForm(num) {
  $(`#var_form_${num}`).remove();
}