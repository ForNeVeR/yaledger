# Отчёт holds — резервы по счетам

## Описание

Отчёт выводит данные о холдах, открытых на указанных счетах за отчётный период.

## Параметры

Один необязательный параметр — счёт или группа счетов, по которым выводить резервы. Если не указан, то выводятся резервы по всем счетам.

Опции:

* `-o`, `--only-open`. Показывать только счета, которые были открыты на конец отчётного периода.
* `-C`, `--csv`. Если указано, то отчёт выводится в виде CSV.

## Примеры вызова

Все резервы по всем счетам:

    $ yaledger holds
    From the begining till 2012/12/30, 00:13:18
    Root/активы/карман:
         DATE     |  SIGN  |       ACCOUNT        |  AMOUNT  |    CLOSE     |    
    ==============|========|======================|==========|==============|    
     2012/12/12   |   DR   | Root/активы/карман   |   25.00р | NA           |    
     2012/12/01   |   DR   | Root/активы/карман   |   50.00р | 2012/12/02   |    

    Root/движение/расходы/трамвай:
         DATE     |  SIGN  |          ACCOUNT           |  AMOUNT  |    CLOSE     |    
    ==============|========|============================|==========|==============|    
     2012/12/10   |   CR   | движение/расходы/трамвай   |   20.00р | 2012/12/11   |    
     2012/12/01   |   CR   | движение/расходы/трамвай   |   50.00р | 2012/12/10   |

Резервы по группе счетов, открытые на заданную дату:

    $ yaledger -E 12/05 holds -o расходы
    From the begining till 2012/12/05
    Root/движение/расходы/трамвай:
         DATE     |  SIGN  |          ACCOUNT           |  AMOUNT  |    CLOSE     |   
    ==============|========|============================|==========|==============|   
     2012/12/01   |   CR   | движение/расходы/трамвай   |   50.00р | 2012/12/10   |

