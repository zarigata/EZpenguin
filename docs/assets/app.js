'use strict';
(() => {
  document.documentElement.classList.add('js');
  const cards = Array.from(document.querySelectorAll('.app'));
  const filters = Array.from(document.querySelectorAll('.filter'));
  const input = document.getElementById('software-search');
  const count = document.getElementById('result-count');
  const showAll = document.getElementById('show-all');
  const clear = document.getElementById('reset-search');
  let category = 'all';
  let expanded = false;

  function update() {
    const query = input.value.trim().toLowerCase();
    const matching = cards.filter(card =>
      (category === 'all' || card.dataset.category === category) &&
      (!query || card.dataset.search.includes(query)));
    const filtered = category !== 'all' || query !== '';
    cards.forEach(card => {
      card.hidden = !matching.includes(card);
      card.classList.toggle('preview-hidden', !expanded && !filtered && matching.indexOf(card) >= 9);
    });
    const visible = !expanded && !filtered ? Math.min(9, matching.length) : matching.length;
    count.textContent = 'Showing ' + visible + ' of ' + matching.length + ' stacks';
    document.getElementById('empty-results').hidden = matching.length !== 0;
    clear.hidden = !filtered;
    showAll.hidden = filtered || matching.length <= 9;
    showAll.textContent = expanded ? 'Show fewer stacks ↑' : 'Show all ' + cards.length + ' stacks ↓';
    showAll.setAttribute('aria-expanded', String(expanded));
    filters.forEach(button => button.setAttribute('aria-pressed', String(button.dataset.category === category)));
  }
  document.getElementById('catalog-controls').hidden = false;
  filters.forEach(button => button.addEventListener('click', () => {
    category = button.dataset.category;
    update();
  }));
  input.addEventListener('input', update);
  clear.addEventListener('click', () => {
    category = 'all'; input.value = ''; expanded = false; update(); input.focus();
  });
  showAll.addEventListener('click', () => {
    expanded = !expanded;
    update();
    if (!expanded) document.getElementById('software').scrollIntoView({block: 'start'});
  });
  update();

  const status = document.getElementById('copy-status');
  async function copy(text, button) {
    const previous = button.textContent;
    try {
      await navigator.clipboard.writeText(text);
      button.textContent = 'Copied ✓';
      status.textContent = 'Install command copied.';
      setTimeout(() => { button.textContent = previous; }, 1800);
    } catch (_error) {
      status.textContent = 'Clipboard unavailable. Select and copy the displayed command.';
      button.textContent = 'Select the command above';
      setTimeout(() => { button.textContent = previous; }, 2500);
    }
  }
  document.querySelectorAll('[data-copy], [data-copy-target]').forEach(button => {
    button.hidden = false;
    button.addEventListener('click', () => copy(
      button.dataset.copy || document.getElementById(button.dataset.copyTarget).textContent, button));
  });

  const tabs = Array.from(document.querySelectorAll('[role="tab"]'));
  function selectTab(tab, moveFocus) {
    tabs.forEach(item => {
      const active = item === tab;
      item.setAttribute('aria-selected', String(active));
      item.tabIndex = active ? 0 : -1;
      document.getElementById(item.getAttribute('aria-controls')).hidden = !active;
    });
    if (moveFocus) tab.focus();
  }
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => selectTab(tab, false));
    tab.addEventListener('keydown', event => {
      let next = index;
      if (event.key === 'ArrowDown' || event.key === 'ArrowRight') next = (index + 1) % tabs.length;
      else if (event.key === 'ArrowUp' || event.key === 'ArrowLeft') next = (index + tabs.length - 1) % tabs.length;
      else if (event.key === 'Home') next = 0;
      else if (event.key === 'End') next = tabs.length - 1;
      else return;
      event.preventDefault();
      selectTab(tabs[next], true);
    });
  });
  selectTab(tabs[0], false);
})();
