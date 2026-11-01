'use strict';
(() => {
  const search = document.getElementById('wiki-query');
  const cards = Array.from(document.querySelectorAll('.software-guide'));
  if (cards.length) {
    const query = new URLSearchParams(location.search).get('q') || '';
    search.value = query;
    function update() {
      const value = search.value.trim().toLowerCase();
      let count = 0;
      cards.forEach(card => {
        card.hidden = !!value && !card.dataset.search.includes(value);
        if (!card.hidden) count += 1;
      });
      document.querySelectorAll('.wiki-category').forEach(section => {
        section.hidden = !Array.from(section.querySelectorAll('.software-guide')).some(card => !card.hidden);
      });
      document.getElementById('wiki-search-status').textContent = count + ' of ' + cards.length + ' software guides';
      document.getElementById('wiki-empty').hidden = count !== 0;
    }
    search.addEventListener('input', update);
    search.closest('form').addEventListener('submit', event => {
      event.preventDefault();
      update();
      document.getElementById('directory').scrollIntoView({block:'start'});
    });
    update();
  }
  document.querySelectorAll('.wiki-copy').forEach(button => {
    button.hidden = false;
    button.addEventListener('click', async () => {
      const status = document.getElementById('wiki-copy-status');
      try {
        await navigator.clipboard.writeText(document.getElementById(button.dataset.code).textContent);
        button.textContent = 'Copied ✓';
        status.textContent = 'Commands copied. Review placeholders before running them.';
      } catch (_error) {
        button.textContent = 'Select the commands above';
        status.textContent = 'Clipboard unavailable. Select and copy the displayed commands.';
      }
    });
  });
})();
