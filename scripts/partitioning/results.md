| Сценарий | Таблица | TPS | Средняя задержка, мс |
|---|---|---:|---:|
| by_user | orders_plain | 29501 | 0.271 |
| by_user | orders_range | 24712 | 0.324 |
| by_user | orders_hash | 25024 | 0.320 |
| by_id | orders_plain | 33200 | 0.241 |
| by_id | orders_range | 29662 | 0.270 |
| by_id | orders_hash | 30211 | 0.265 |
| by_period | orders_plain | 666 | 12.011 |
| by_period | orders_range | 1185 | 6.753 |
| by_period | orders_hash | 679 | 11.778 |
| mixed | orders_plain | 9570 | 0.836 |
| mixed | orders_range | 12136 | 0.659 |
| mixed | orders_hash | 8783 | 0.911 |
| insert | orders_plain | 24097 | 0.332 |
| insert | orders_range | 23962 | 0.334 |
| insert | orders_hash | 24022 | 0.333 |
