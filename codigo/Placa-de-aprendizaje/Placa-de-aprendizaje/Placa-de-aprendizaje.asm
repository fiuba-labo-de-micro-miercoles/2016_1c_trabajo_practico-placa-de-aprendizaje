/*
 * Ejercicio1.asm
 *
 *  Created: 15/9/2015 12:24:18 p. m.
 *   Author: alandex
 */ 

.INCLUDE "m2560def.inc"			//Incluye definición archivos ATMEGA2560

//.equ	MEDICIONES	= 4
.equ	ADMUX_INICIO = 0x00 ; (codigo implememteado para 5 bits de MUX) desde A0
.equ	ADMUX_FIN	 = 0x07 ; leo hasta A7
.equ	MASCARA_ADMUX = 0x17
.equ	INICIO_DE_TRAMA = 0x5A

; ***** DEFINICION DE REGISTROS ************
.def	CRC	= r24; Cyclic Redundancy Check

; ESTADO - registro encargado de registrar el estado actual del programa mediante flags
.def	ESTADO	= r25
; bit 7 = Flag que se activa si esta en modo generador
; bit 6 = Flag que se activa al final de las mediciones

; ***** BIT DEFINITIONS **************************************************
.equ	MODO_GENERADOR	= 0	; Flag que se activa si esta en modo generador
.equ	FIN_DE_MEDICIONES	= 1	; Flag que se activa al final de las mediciones

; definiciones de la salida de las mediciones
.equ	Pin_A0	= 7
.equ	Pin_A1	= 0
.equ	Pin_A2	= 0
.equ	Pin_A3	= 0
.equ	Pin_A4	= 0
.equ	Pin_A5	= 0
.equ	Pin_A6	= 0
.equ	Pin_A7	= 0

.equ	PORT_A0 = PORTB
.equ	PORT_A1 = PORTB
.equ	PORT_A2 = PORTB
.equ	PORT_A3 = PORTB
.equ	PORT_A4 = PORTB
.equ	PORT_A5 = PORTB
.equ	PORT_A6 = PORTB
.equ	PORT_A7 = PORTB

.equ	DDR_A0 = DDRB
.equ	DDR_A1 = DDRB
.equ	DDR_A2 = DDRB
.equ	DDR_A3 = DDRB
.equ	DDR_A4 = DDRB
.equ	DDR_A5 = DDRB
.equ	DDR_A6 = DDRB
.equ	DDR_A7 = DDRB


;Se abre un segmento de datos para definir variables
.dseg 
.org	SRAM_START // 0x200
; Definición de variables en la zona de memoria de uso general

muestreo: 	.byte	2 /* *MEDICIONES */   ;Variable que guarda el muestreo de la medicion actual (cada valor medido ocupa 2 bytes)
//trama: 	.byte	10    ;Variable que guarda los promedios de las mediciones (de 2 bytes cada uno) para luego ser enviados

;Se abre un segmente de código flash para escribir instrucciones o tablas.
.cseg
.ORG $00
RJMP RESET			// Reset

.org	ADCCaddr		; definido en m2560def.inc (0x003a)
rjmp	ISR_CONV_ADC_COMPLETA

.ORG INT_VECTORS_SIZE // salteo el vector de interrupciones
RESET:
	// mueve el stack pointer al final de la RAM para maximizar el espacio de STACK
	LDI R16,LOW(RAMEND)
	OUT SPL,R16
	LDI R16,HIGH(RAMEND)
	OUT SPH,R16
	
	ldi r16,0x00
	out DDRF,r16 ;configura todo el puerto F como entradas (analogicas)

	; control de salidas correspondientes a los valores medidos
	ldi r16,0xFF
	out DDRD,r16 ;configura todo el puerto D como salidas (digitales)
	out DDRB,r16 ;configura todo el puerto B como salidas (digitales)

	; configura los pines de salida de las mediciones
	sbi DDR_A0, Pin_A0
	sbi DDR_A1, Pin_A1
	sbi DDR_A2, Pin_A2
	sbi DDR_A3, Pin_A3
	sbi DDR_A4, Pin_A4
	sbi DDR_A5, Pin_A5
	sbi DDR_A6, Pin_A6
	sbi DDR_A7, Pin_A7

	clr ESTADO

	; configuro baud rate de 250k (ver tabla pagina 226 de la datasheet)  error = 0%
	clr r17    
	ldi r16, 7
//	clr r16
//	inc r16
//	ldi r16, 207 ; baud rate de 9600
//	ldi r17, high(832)
//	ldi r16, low(832) ; baud rate de 2400
	
	rcall USART_Init ; inicializo USART

reinicio_mediciones:
	ldi CRC, INICIO_DE_TRAMA ; sumo el inicio de trama al CRC

	ldi r16, INICIO_DE_TRAMA
	rcall USART_Transmit ; transmito el inicio de trama
	rcall ADC_Primera_Medicion ; configuro y comienzo primera medicion

principal:
	sbrc ESTADO, MODO_GENERADOR
	rjmp generador
	sbrs ESTADO, FIN_DE_MEDICIONES
	rjmp principal

	

	; leo la medicion actual
	lds		r20, muestreo
	lds		r16, muestreo+1
	

	rcall procesar_medicion ; proceso la medicion

	andi ESTADO, ~(1<<FIN_DE_MEDICIONES) ; limpio el flag de FIN_DE_MEDICIONES

	; sumo la mediciona actual al CRC
	add CRC, r20
	add CRC, r16

	; envio la medicion actual
	rcall USART_Transmit
	mov r16, r20
	rcall USART_Transmit

	; me fijo si es la ultima medicion
	lds	r16,ADMUX
	ldi r17, MASCARA_ADMUX
	and r17, r16 ; hago unba mascara para solo quedarme con el MUX4:0
	cpi r17, ADMUX_FIN	; ultimo pin a leer
	breq enviar_fin_de_trama
	//lds	r16,ADMUX

	inc r16			; convierto desde el siguiente pin
	sts	ADMUX,r16	; escribe reg. ADMUX de configuración del ADC

	; envio a medir la siguiente conversion
	lds	r16,ADCSRA
	ori r16,(1<<ADSC); escribo ADSC en uno para iniciar siguiente conversion.
	sts ADCSRA,r16

	rjmp principal

enviar_fin_de_trama:
	neg CRC
	mov r16, CRC
	rcall USART_Transmit

		//prendo y apago un LED
//	ser R18 ; R16 a unos
//	out PORTB,R18 ;Pone todas las patillas de B a uno
	rcall retardo
//	clr R18 ; R16 a ceros
//	out PORTB,R18 ;Pone todas las patillas de B a cero
//	rcall retardo





	rjmp reinicio_mediciones

generador:
	cbr ESTADO, MODO_GENERADOR
	rjmp principal

ADC_Primera_Medicion:	
	cli ; SREG<I>=0 interrupciones globales deshabilitadas
	;	sbi DIDR0,ADC0D ; dehabilito el buffer de la entrada digital del pin, lo que permite reducir el consumo de potencia.

	; importante, la seleccion del MUX siempre debe hacerse ANTES de iniciar la conversion 
	; (puede hacerse durante la conversion anterior despues de que baje ADIF)

	ldi	r16,(0<<REFS1)|(1<<REFS0)|(0<<ADLAR)|ADMUX_INICIO ; ADMUX son los bits bajos, 4:0
		; (0<<REFS1)|(1<<REFS0): Referencia interna AVCC (5V)
		; (0<<ADLAR): Ajuste a derecha del resultado
		; (0<<MUX4)|(0<<MUX3)|(0<<MUX2)|(0<<MUX1)|(0<<MUX0): Convierto la tensión desde PF0 (ADC0)
	sts	ADMUX,r16	; escribe reg. ADMUX de configuración del ADC

//	lds	r16,ADCSRB	; reg. de configuración que contiene el sexto bit del canal del ADC (MUX5)
	ldi	r16,(0<<MUX5)|(0<<ADTS2)|(0<<ADTS1)|(0<<ADTS0) ; los demas bits los pongo en cero, no son relevantes
		; (0<<MUX5): para los canales F0:7 debe valer 0, de F8:15 debe valer 1
		; (0<<ADTS2)|(0<<ADTS1)|(0<<ADTS0): Free runing
	sts	ADCSRB,r16	; escribe reg. B de configuración del ADC

	ldi r16,(1<<ADEN)|(1<<ADSC)|(0<<ADATE)|(0<<ADIF)|(1<<ADIE)|(1<<ADPS2)|(1<<ADPS1)|(1<<ADPS0)
		; (1<<ADEN): Habilita el ADC
		; (1<<ADSC): Pedido de 1er conversión (inicia)
		; (0<<ADATE):  permite el auto triggering, por ejemplo: conversion continua (si esta en cero solo inicia medicion con ADSC en 1)
		; (0<<ADIF): Limpio posible interrupcion falsa
		; (1<<ADIE): Interrumpe cada vez que termina una conversión	
		; (1<<ADPS2)|(1<<ADPS1)|(1<<ADPS0): 16MHz/128 = 125 kHz                   con 000 seria mucho mas rapido
			; primera conversion en (25/125k) = 200 uSeg
			; siguiente conversion en (13/125k) = 104 uSeg
	sts ADCSRA,r16		; escribe reg. A de configuración del ADC / se inicia primera conversion

		/*	otra forma, uno a uno...
		sbi ADCSRA,ADIF ; limpio posible interrupcion falsa
		Cbi ADCSRA,ADIF ;*/

	sei ; habilito interrupciones globales
	ret

; procesa la medicion actual
procesar_medicion:
//	lds		r20, muestreo bit bajo
//	lds		r16, muestreo+1

	; me fijo cual medicion es
	lds	r18,ADMUX
	ldi r17, MASCARA_ADMUX
	and r17, r18 ; hago una mascara para solo quedarme con el MUX4:0
	
	; switch 
	cpi r17, 0
	breq procesar_A0
	cpi r17, 1
	breq procesar_A1
	cpi r17, 2
	breq procesar_A2
	cpi r17, 3
	breq procesar_A3
	cpi r17, 4
	breq procesar_A4
	cpi r17, 5
	breq procesar_A5
	cpi r17, 6
	breq procesar_A6
	cpi r17, 7
	breq procesar_A7
	rjmp default

procesar_A0:
	; ventana = [A0_limite_inferior, A0_limite_superior]
	; si el valor no esta incluido en la ventana, habilita la salida.

	.equ	A0_limite_superior_H = 0x02 ; superior 3.3 V, 675, 0x02A3
	.equ	A0_limite_superior_L = 0xA3
	.equ	A0_limite_inferior_H = 0x01 ; inferior 1.7 V, 348, 0x015C
	.equ	A0_limite_inferior_L = 0x5C

	; comparo con limite inferior
	ldi r17, A0_limite_inferior_H
	cpi r20, A0_limite_inferior_L ; comparo los bits bajos
	cpc r16, r17 ; comparo los bits altos
	brlo A0_afuera_de_ventana ; afuera por limite inferior

	; comparo con limite superior
	ldi r17, A0_limite_superior_H
	cpi r20, A0_limite_superior_L ; comparo los bits bajos
	cpc r16, r17 ; comparo los bits altos
	brlo A0_adentro_de_ventana
	breq A0_adentro_de_ventana
	; afuera por limite superior

A0_afuera_de_ventana:
	sbi PORT_A0, Pin_A0 ; prende el pin correspondiente
	rjmp fin_procesar_A0

A0_adentro_de_ventana:
	cbi PORT_A0, Pin_A0 ; apago el pin correspondiente

fin_procesar_A0:
	rjmp fin_switch

procesar_A1:
/*
	; si el valor medido supera el maximo, se habilita la salida

	.equ	A1_maximo_H = 0x02 ;  3.3 V, 675, 0x02A3
	.equ	A1_maximo_L = 0xA3

	; comparo con el maximo
	ldi r17, A1_maximo_H
	cpi r20, A1_maximo_L ; comparo los bits bajos
	cpc r16, r17 ; comparo los bits altos
	brlo A1_menor_o_igual_al_maximo ; menor al maximo
	breq A1_menor_o_igual_al_maximo ; igual al maximo
	; mayor al maximo

A1_mayor_al_maximo:
	sbi PORT_A1, Pin_A1 ; prende el pin correspondiente
	rjmp fin_procesar_A1

A1_menor_o_igual_al_maximo:
	cbi PORT_A1, Pin_A1 ; apago el pin correspondiente
*/
fin_procesar_A1:
	rjmp fin_switch

procesar_A2:
	rjmp fin_switch
procesar_A3:
	rjmp fin_switch
procesar_A4:
	rjmp fin_switch
procesar_A5:
	rjmp fin_switch
procesar_A6:
	rjmp fin_switch
procesar_A7:
	rjmp fin_switch
default: 
	/* no hago nada*/
fin_switch:
	ret




///// IMPLEMENTACION DE FUNCIONES DE USART, segun Datasheet ///////////

USART_Init:
	; Set baud rate
	sts UBRR0H, r17
	sts UBRR0L, r16

;	ldi r16, 0x00
;	sts UCSR0A, r16

	ldi r16, (1<<U2X0) ; dobla la velocidad de transmision en modo asincronico
	sts UCSR0A, r16
	; Enable receiver and transmitter
	ldi r16, (1<<RXEN0)|(1<<TXEN0) ;  (0<<UCSZ02)  (ademas: todas las interrupciones desactivadas)
	sts UCSR0B, r16
	; Set frame format: 8data, 1stop bit
	ldi r16, (1<<UCSZ01)|(1<<UCSZ00); asincronico, paridad disable, 1 stop bit, 8 data (011, el tercer bit esta en UCSR0B)
	sts UCSR0C, r16
	ret

USART_Transmit:
	; Wait for empty transmit buffer
	lds r17, UCSR0A
	sbrs r17, UDRE0 ; esta vacio el buffer de salida???
	rjmp USART_Transmit
	; Put data (r16) into buffer, sends the data
	sts UDR0, r16
	ret

USART_Receive:
	; Wait for data to be received
	lds r17, UCSR0A
	sbrs r17, RXC0 ; llego nuevo dato??
	rjmp USART_Receive
	; Get and return received data from buffer
	lds r16, UDR0
	ret

/////////// FIN USART //////////////////////////////////////////////////////////////////


;-------------------------------------------------------------------------
; Rutina de Servicio de Interrupción (ISR) del conversor ADC
;-------------------------------------------------------------------------
ISR_CONV_ADC_COMPLETA:
; limpia automaticamente el bit ADIF
; copio el resultado de la conversión a la variable "muestreo"
	lds		r20,ADCL		; se lee 1ro el byte bajo
	lds		r21,ADCH		; y luego el alto
	sts		muestreo,r20
	sts		muestreo+1,r21

	ori ESTADO, (1<<FIN_DE_MEDICIONES) ; seteo el flag FIN_DE_MEDICIONES
	reti

 





 /*   codigo extra    */

retardo: ; 1 segundo para 16 MHz
push r16
push r17
push r18
	ldi r16,3
	ldi r17,44
	ldi r18,82
loop:
	dec R16
	brne LOOP
	dec R17
	brne LOOP
	dec R18
	brne LOOP
	rjmp (PC+1)


	pop r18
	pop r17
	 pop r16
ret


.exit  



	//prendo y apago un LED
	ser R18 ; R16 a unos
	out PORTB,R18 ;Pone todas las patillas de B a uno
	rcall retardo
	clr R18 ; R16 a ceros
	out PORTB,R18 ;Pone todas las patillas de B a cero
	rcall retardo





	; no haria falta
	cbi DDRE,0 ; Pin RXD0 como entrada
	sbi DDRE,1 ; Pin TXD0 como salida
















	
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////   
//  CODIGO pende y apaga dos veces y luego pasa al led lo leido por A

	ser R16 ; R16 a unos
	out DDRB,R16 ;Configura todo el puerto B como salidas

	clr R16 ; R16 a ceros
	out DDRA,R16 ;Configura todo el puerto A como entradas


;	out PORTB,R16 ;Pone todas las patillas de B a uno

;**** Parpadeo   loop ppal
;blink:

; prendo y apago dos veces

	ser R16 ; R16 a unos
	out PORTB,R16 ;Pone todas las patillas de B a uno
	rcall retardo
	clr R16 ; R16 a ceros
	out PORTB,R16 ;Pone todas las patillas de B a cero
	rcall retardo

;	rjmp blink


	ser R16 ; R16 a unos
	out PORTB,R16 ;Pone todas las patillas de B a uno
	rcall retardo
	clr R16 ; R16 a ceros
	out PORTB,R16 ;Pone todas las patillas de B a cero
	rcall retardo


	;leo lo que hay en el puerto A y lo paso al led.    (conectar pin 29 con GND o VCC)

blink:
	in R16, PINA ; leo el puerto A y lo copio en un registro
	out PORTB,R16 ;Pone todas las patillas de B con el contenido de A
rjmp blink
;	SBI PORTB,7 ;set PORTB.7
;	CBI PORTB,7 ;clr PORTB.7


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////// 

